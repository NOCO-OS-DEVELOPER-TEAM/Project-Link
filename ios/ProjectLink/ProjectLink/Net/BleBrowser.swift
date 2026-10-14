import Foundation
import CoreBluetooth

/// Discovers Project Link PCs advertising BLE manufacturer data (IP + port), then Wi‑Fi takes over for speed.
@MainActor
final class BleBrowser: NSObject, ObservableObject {
    @Published var found: [BlePeer] = []
    @Published var scanning = false
    @Published var status = "Bluetooth idle"

    struct BlePeer: Identifiable, Equatable {
        let id: UUID
        let name: String
        let ip: String
        let port: Int
    }

    private var central: CBCentralManager?
    private let serviceUUID = CBUUID(string: "6C4E-4B31-0001-0001-000000000001") // LNK1-ish

    func start() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        } else if central?.state == .poweredOn {
            beginScan()
        }
    }

    func stop() {
        scanning = false
        central?.stopScan()
        status = "Bluetooth stopped"
    }

    private func beginScan() {
        found.removeAll()
        scanning = true
        status = "Scanning BLE…"
        central?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }
}

extension BleBrowser: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn: beginScan()
            case .poweredOff: status = "Bluetooth off"; scanning = false
            case .unauthorized: status = "Bluetooth permission denied"
            default: status = "Bluetooth unavailable"
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        // Expect local name "ProjectLink" and manufacturer data: magic(4)='LNK1' + ipv4(4) + port(2 BE)
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? ""
        guard name.contains("ProjectLink") || name.contains("LINK") else { return }
        guard let mfg = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
              mfg.count >= 10 else { return }
        // Skip company id (2 bytes) if present — Windows may send raw payload differently
        let payload: Data
        if mfg.count >= 12, String(bytes: mfg[2..<6], encoding: .ascii) == "LNK1" {
            payload = mfg.subdata(in: 2..<mfg.count)
        } else if String(bytes: mfg[0..<4], encoding: .ascii) == "LNK1" {
            payload = mfg
        } else {
            return
        }
        guard payload.count >= 10 else { return }
        let b = [UInt8](payload)
        let ip = "\(b[4]).\(b[5]).\(b[6]).\(b[7])"
        let port = (Int(b[8]) << 8) | Int(b[9])
        let peer = BlePeer(id: peripheral.identifier, name: name, ip: ip, port: port)
        Task { @MainActor in
            if !found.contains(where: { $0.ip == peer.ip }) {
                found.append(peer)
                status = "Found \(peer.name) @ \(peer.ip)"
            }
        }
    }
}
