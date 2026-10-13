import Foundation
import Network
import UIKit
import ReplayKit
import CoreMedia
import CoreImage

@MainActor
final class PcScreenReceiver: ObservableObject {
    @Published var image: UIImage?
    @Published var fps: Int = 0
    @Published var connected = false
    @Published var error: String?

    private var connection: NWConnection?
    private var buffer = Data()
    private var frames = 0
    private var lastFpsAt = Date()

    func start(host: String) {
        stop()
        error = nil
        let h = NWEndpoint.Host(host)
        let p = NWEndpoint.Port(rawValue: UInt16(LinkPorts.screenOut))!
        let conn = NWConnection(host: h, port: p, using: .tcp)
        connection = conn
        conn.stateUpdateHandler = { [weak self] st in
            Task { @MainActor in
                switch st {
                case .ready:
                    self?.connected = true
                    self?.receive()
                case .failed(let e):
                    self?.connected = false
                    self?.error = e.localizedDescription
                default: break
                }
            }
        }
        conn.start(queue: .global(qos: .userInitiated))
    }

    func stop() {
        connection?.cancel()
        connection = nil
        connected = false
        buffer.removeAll()
    }

    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 2_000_000) { [weak self] content, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return }
                if let content {
                    self.buffer.append(content)
                    self.consume()
                }
                if isComplete || error != nil {
                    self.connected = false
                    return
                }
                self.receive()
            }
        }
    }

    private func consume() {
        while buffer.count >= 4 {
            let len: UInt32 = buffer.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            let total = 4 + Int(len)
            guard len > 0, len < 8_000_000, buffer.count >= total else { return }
            let jpeg = Data(buffer[4..<total])
            buffer.removeSubrange(0..<total)
            if let img = UIImage(data: jpeg) {
                image = img
                frames += 1
                let now = Date()
                if now.timeIntervalSince(lastFpsAt) >= 1 {
                    fps = frames
                    frames = 0
                    lastFpsAt = now
                }
            }
        }
    }
}

/// Streams iPhone frames to PC :47803 using ReplayKit sample buffers (app / system capture).
@MainActor
final class PhoneScreenStreamer: ObservableObject {
    @Published var streaming = false
    @Published var error: String?
    @Published var sentFps = 0

    private var connection: NWConnection?
    private var frames = 0
    private var lastFpsAt = Date()
    private var lastSend = Date.distantPast
    private let minInterval: TimeInterval = 1.0 / 18.0

    func start(host: String) {
        stop()
        error = nil
        LinkClient.shared.notifyPhoneStream()
        let h = NWEndpoint.Host(host)
        let p = NWEndpoint.Port(rawValue: UInt16(LinkPorts.screenIn))!
        let conn = NWConnection(host: h, port: p, using: .tcp)
        connection = conn
        conn.stateUpdateHandler = { [weak self] st in
            Task { @MainActor in
                switch st {
                case .ready:
                    self?.beginReplayKit()
                case .failed(let e):
                    self?.error = e.localizedDescription
                    self?.streaming = false
                default: break
                }
            }
        }
        conn.start(queue: .global(qos: .userInitiated))
    }

    func stop() {
        if RPScreenRecorder.shared().isRecording {
            RPScreenRecorder.shared().stopCapture { _ in }
        }
        connection?.cancel()
        connection = nil
        streaming = false
    }

    private func beginReplayKit() {
        let recorder = RPScreenRecorder.shared()
        guard recorder.isAvailable else {
            error = "ReplayKit unavailable"
            return
        }
        recorder.isMicrophoneEnabled = false
        recorder.startCapture { [weak self] sample, bufferType, err in
            guard bufferType == .video, err == nil, let self else { return }
            Task { @MainActor in
                self.handle(sample)
            }
        } completionHandler: { [weak self] err in
            Task { @MainActor in
                if let err {
                    self?.error = err.localizedDescription
                    self?.streaming = false
                } else {
                    self?.streaming = true
                    LinkClient.shared.log("Phone→PC ReplayKit capture started")
                }
            }
        }
    }

    private func handle(_ sample: CMSampleBuffer) {
        let now = Date()
        guard now.timeIntervalSince(lastSend) >= minInterval else { return }
        lastSend = now
        guard let jpeg = Self.jpeg(from: sample, quality: 0.45, maxWidth: 720) else { return }
        var len = UInt32(jpeg.count).bigEndian
        var packet = Data(bytes: &len, count: 4)
        packet.append(jpeg)
        connection?.send(content: packet, completion: .contentProcessed { _ in })
        frames += 1
        if now.timeIntervalSince(lastFpsAt) >= 1 {
            sentFps = frames
            frames = 0
            lastFpsAt = now
        }
    }

    private static func jpeg(from sample: CMSampleBuffer, quality: CGFloat, maxWidth: CGFloat) -> Data? {
        guard let pb = CMSampleBufferGetImageBuffer(sample) else { return nil }
        let ci = CIImage(cvPixelBuffer: pb)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cg = context.createCGImage(ci, from: ci.extent) else { return nil }
        let ui = UIImage(cgImage: cg)
        let scale = min(1, maxWidth / ui.size.width)
        let size = CGSize(width: ui.size.width * scale, height: ui.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let scaled = renderer.image { _ in ui.draw(in: CGRect(origin: .zero, size: size)) }
        return scaled.jpegData(compressionQuality: quality)
    }
}
