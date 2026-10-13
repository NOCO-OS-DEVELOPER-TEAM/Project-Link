import Foundation
import Network
import UIKit

@MainActor
final class LinkClient: ObservableObject {
    static let shared = LinkClient()

    @Published var state: ConnState = .idle
    @Published var pcName: String = ""
    @Published var rttMs: Int = 0
    @Published var logs: [String] = []
    @Published var clipboardPreview: String = ""
    @Published var lastError: String?

    enum ConnState: String {
        case idle, connecting, paired, failed
    }

    let deviceId = (UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString)
        .replacingOccurrences(of: "-", with: "")
        .prefix(12)
        .description
    let deviceName = UIDevice.current.name

    private var connection: NWConnection?
    private var inputConn: NWConnection?
    private var seq: UInt32 = 0
    private var receiveBuffer = Data()
    private var pcHost: String = ""
    private var pairingToken: String = ""
    private var pcDeviceId: String = ""
    private var latencyTimer: Timer?
    var sensitivity: Float = 1.35
    var clipboardSyncEnabled = false
    private var lastClipboardSent = ""
    private var suppressClipboard = false

    var host: String { pcHost }
    var isPaired: Bool { state == .paired }

    func log(_ m: String) {
        let line = "[\(Self.stamp())] \(m)"
        logs.insert(line, at: 0)
        if logs.count > 300 { logs.removeLast(logs.count - 300) }
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }

    func connect(from payload: PairingPayload) {
        disconnect()
        pcHost = payload.ip
        pairingToken = payload.t
        pcDeviceId = payload.id
        pcName = payload.n
        state = .connecting
        lastError = nil
        log("Connecting \(payload.ip):\(payload.p)…")

        let host = NWEndpoint.Host(payload.ip)
        let port = NWEndpoint.Port(rawValue: UInt16(payload.p))!
        let conn = NWConnection(host: host, port: port, using: .tcp)
        connection = conn
        conn.stateUpdateHandler = { [weak self] st in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch st {
                case .ready:
                    self.log("TCP ready")
                    self.startReceive()
                    self.sendPairRequest()
                    self.setupInputUDP()
                    self.startLatency()
                case .failed(let e):
                    self.state = .failed
                    self.lastError = e.localizedDescription
                    self.log("TCP failed: \(e.localizedDescription)")
                case .waiting(let e):
                    self.log("TCP waiting: \(e.localizedDescription)")
                default: break
                }
            }
        }
        conn.start(queue: .global(qos: .userInteractive))
    }

    func connect(qrJSON: String) {
        guard let data = qrJSON.data(using: .utf8),
              let payload = try? JSONDecoder().decode(PairingPayload.self, from: data) else {
            lastError = "Invalid QR payload"
            state = .failed
            return
        }
        connect(from: payload)
    }

    func disconnect() {
        latencyTimer?.invalidate()
        latencyTimer = nil
        connection?.cancel()
        connection = nil
        inputConn?.cancel()
        inputConn = nil
        receiveBuffer.removeAll()
        if state != .idle { log("Disconnected") }
        state = .idle
    }

    private func setupInputUDP() {
        let host = NWEndpoint.Host(pcHost)
        let port = NWEndpoint.Port(rawValue: UInt16(LinkPorts.inputUdp))!
        let conn = NWConnection(host: host, port: port, using: .udp)
        inputConn = conn
        conn.start(queue: .global(qos: .userInteractive))
        log("UDP input → :\(LinkPorts.inputUdp)")
    }

    func sendInput(flags: UInt16, dx: Int16 = 0, dy: Int16 = 0, wheel: Int16 = 0, vk: UInt16 = 0, mods: UInt16 = 0) {
        guard state == .paired, let inputConn else { return }
        seq &+= 1
        let scaledDx = Int16(clamping: Int(Float(dx) * sensitivity))
        let scaledDy = Int16(clamping: Int(Float(dy) * sensitivity))
        let packet = InputPacket.build(seq: seq, flags: flags, dx: scaledDx, dy: scaledDy, wheel: wheel, vk: vk, mods: mods)
        inputConn.send(content: packet, completion: .contentProcessed { _ in })
    }

    func move(dx: CGFloat, dy: CGFloat) {
        sendInput(flags: InputFlags.move.rawValue, dx: Int16(clamping: Int(dx.rounded())), dy: Int16(clamping: Int(dy.rounded())))
    }

    func leftDown() { sendInput(flags: InputFlags.leftDown.rawValue) }
    func leftUp() { sendInput(flags: InputFlags.leftUp.rawValue) }
    func rightDown() { sendInput(flags: InputFlags.rightDown.rawValue) }
    func rightUp() { sendInput(flags: InputFlags.rightUp.rawValue) }
    func doubleClick() { sendInput(flags: InputFlags.doubleClick.rawValue) }
    func wheel(_ delta: Int16) { sendInput(flags: InputFlags.wheel.rawValue, wheel: delta) }
    func key(_ vk: UInt16, down: Bool, mods: UInt16 = 0) {
        sendInput(flags: down ? InputFlags.keyDown.rawValue : InputFlags.keyUp.rawValue, vk: vk, mods: mods)
    }

    func media(_ action: String) {
        sendJSON(.mediaKey, MediaKeyMsg(action: action))
    }

    func launch(_ query: String) {
        sendJSON(.launchApp, LaunchAppMsg(query: query))
    }

    func sendClipboard(_ text: String) {
        guard clipboardSyncEnabled, !text.isEmpty, text != lastClipboardSent else { return }
        lastClipboardSent = text
        let msg = ClipboardMsg(text: text, origin: "phone", ts: Int64(Date().timeIntervalSince1970 * 1000))
        sendJSON(.clipboardText, msg)
        clipboardPreview = text
        log("Clipboard → PC (\(text.count) chars)")
    }

    func requestPcStream(cfg: StreamConfigMsg = StreamConfigMsg(direction: "pc_to_phone", maxWidth: 1280, maxHeight: 720, fps: 28, jpegQuality: 55, touchAsMouse: true)) {
        sendJSON(.streamConfig, cfg)
        sendJSON(.streamStart, cfg)
    }

    func notifyPhoneStream() {
        let cfg = StreamConfigMsg(direction: "phone_to_pc", maxWidth: 720, maxHeight: 1280, fps: 20, jpegQuality: 45, touchAsMouse: false)
        sendJSON(.streamStart, cfg)
    }

    private func sendPairRequest() {
        let req = PairRequestMsg(deviceId: deviceId, name: deviceName, token: pairingToken)
        sendJSON(.pairRequest, req)
    }

    private func startLatency() {
        latencyTimer?.invalidate()
        latencyTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.probeLatency() }
        }
    }

    private func probeLatency() {
        var ts = Int64(Date().timeIntervalSince1970 * 1000).littleEndian
        let data = Data(bytes: &ts, count: 8)
        sendRaw(FrameCodec.encode(type: .latencyProbe, payload: data))
    }

    func sendJSON<T: Encodable>(_ type: MsgType, _ value: T) {
        guard let frame = try? FrameCodec.encodeJSON(type, value) else { return }
        sendRaw(frame)
    }

    func sendRaw(_ frame: Data) {
        connection?.send(content: frame, completion: .contentProcessed { [weak self] err in
            if let err {
                Task { @MainActor [weak self] in self?.log("Send error: \(err.localizedDescription)") }
            }
        })
    }

    private func startReceive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 1024 * 1024) { [weak self] content, _, isComplete, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let content { self.receiveBuffer.append(content); self.consumeFrames() }
                if isComplete || error != nil {
                    if let error { self.log("RX end: \(error.localizedDescription)") }
                    if self.state == .paired { self.state = .failed }
                    return
                }
                self.startReceive()
            }
        }
    }

    private func consumeFrames() {
        while receiveBuffer.count >= 6 {
            let len: UInt32 = receiveBuffer.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            let typeRaw: UInt16 = receiveBuffer.dropFirst(4).prefix(2).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
            let total = 6 + Int(len)
            guard receiveBuffer.count >= total else { return }
            let payload = Data(receiveBuffer[6..<total])
            receiveBuffer.removeSubrange(0..<total)
            handle(MsgType(rawValue: typeRaw), payload)
        }
    }

    private func handle(_ type: MsgType?, _ payload: Data) {
        guard let type else { return }
        switch type {
        case .hello:
            if let h = try? JSONDecoder().decode(HelloMsg.self, from: payload) {
                pcName = h.name
                log("Hello from \(h.name)")
            }
        case .pairAccept:
            if let a = try? JSONDecoder().decode(PairAcceptMsg.self, from: payload) {
                pcName = a.name
                state = .paired
                log("Paired ✓ \(a.name)")
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        case .pairReject:
            state = .failed
            lastError = "Pair rejected"
            log("Pair rejected")
        case .clipboardText:
            if let msg = try? JSONDecoder().decode(ClipboardMsg.self, from: payload), clipboardSyncEnabled {
                suppressClipboard = true
                UIPasteboard.general.string = msg.text
                clipboardPreview = msg.text
                log("Clipboard ← PC")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.suppressClipboard = false }
            }
        case .latencyProbe:
            sendRaw(FrameCodec.encode(type: .latencyReply, payload: payload))
        case .latencyReply:
            if payload.count >= 8 {
                let sent = payload.withUnsafeBytes { $0.load(as: Int64.self).littleEndian }
                let now = Int64(Date().timeIntervalSince1970 * 1000)
                rttMs = max(0, Int(now - sent))
            }
        case .pong:
            break
        default:
            log("Msg \(type.rawValue) (\(payload.count)b)")
        }
    }

    /// Call when app becomes active — push pasteboard if sync on (iOS realistic path).
    func syncClipboardOnForeground() {
        guard clipboardSyncEnabled, state == .paired, !suppressClipboard else { return }
        if let t = UIPasteboard.general.string, !t.isEmpty {
            sendClipboard(t)
        }
    }
}
