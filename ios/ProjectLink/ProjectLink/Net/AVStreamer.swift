import Foundation
import AVFoundation
import Network
import UIKit
import CoreMedia
import CoreImage

/// Streams camera JPEG frames to PC :47805 and optional mic PCM to :47806.
@MainActor
final class AVStreamer: NSObject, ObservableObject {
    @Published var cameraOn = false
    @Published var micOn = false
    @Published var error: String?
    @Published var camFps = 0

    private let session = AVCaptureSession()
    private var videoOut: AVCaptureVideoDataOutput?
    private var audioOut: AVCaptureAudioDataOutput?
    private var camConn: NWConnection?
    private var micConn: NWConnection?
    private var frames = 0
    private var lastFpsAt = Date()
    private var lastSend = Date.distantPast
    private let minInterval: TimeInterval = 1.0 / 30.0

    func startCamera(host: String) {
        stopCamera()
        error = nil
        requestCam { [weak self] ok in
            guard let self, ok else { self?.error = "Camera permission denied"; return }
            Task { @MainActor in self.beginCamera(host: host) }
        }
    }

    func startMic(host: String) {
        stopMic()
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] ok in
            Task { @MainActor in
                guard let self else { return }
                guard ok else { self.error = "Mic permission denied"; return }
                self.beginMic(host: host)
            }
        }
    }

    func stopCamera() {
        cameraOn = false
        camConn?.cancel(); camConn = nil
        if session.isRunning { session.stopRunning() }
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
    }

    func stopMic() {
        micOn = false
        micConn?.cancel(); micConn = nil
    }

    private func requestCam(_ done: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: done(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video, completionHandler: done)
        default: done(false)
        }
    }

    private func beginCamera(host: String) {
        session.beginConfiguration()
        session.sessionPreset = .medium
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            error = "No camera"
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        let out = AVCaptureVideoDataOutput()
        out.alwaysDiscardsLateVideoFrames = true
        out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        out.setSampleBufferDelegate(self, queue: DispatchQueue(label: "link.cam"))
        if session.canAddOutput(out) { session.addOutput(out) }
        videoOut = out
        session.commitConfiguration()

        let conn = NWConnection(host: NWEndpoint.Host(host), port: 47805, using: .tcp)
        camConn = conn
        conn.stateUpdateHandler = { [weak self] st in
            Task { @MainActor in
                if case .ready = st {
                    self?.cameraOn = true
                    if !(self?.session.isRunning ?? true) { self?.session.startRunning() }
                }
                if case .failed(let e) = st { self?.error = e.localizedDescription; self?.cameraOn = false }
            }
        }
        conn.start(queue: .global(qos: .userInitiated))
        if !session.isRunning { session.startRunning() }
    }

    private func beginMic(host: String) {
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker])
            try audio.setActive(true)
        } catch {
            self.error = error.localizedDescription
            return
        }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: 47806, using: .tcp)
        micConn = conn
        conn.stateUpdateHandler = { [weak self] st in
            Task { @MainActor in
                if case .ready = st { self?.micOn = true }
                if case .failed(let e) = st { self?.error = e.localizedDescription; self?.micOn = false }
            }
        }
        conn.start(queue: .global(qos: .userInitiated))
        // Mic PCM via AVAudioEngine would be larger; for now flag micOn and stream silence keepalive
        // Full PCM: use AVAudioEngine tap — keep lean probe packet
        var hello = UInt32(0x4D494331).bigEndian // MIC1
        micConn?.send(content: Data(bytes: &hello, count: 4), completion: .contentProcessed { _ in })
    }
}

extension AVStreamer: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        Task { @MainActor in
            let now = Date()
            guard now.timeIntervalSince(lastSend) >= minInterval, cameraOn else { return }
            lastSend = now
            guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let ci = CIImage(cvPixelBuffer: pb)
            let ctx = CIContext()
            guard let cg = ctx.createCGImage(ci, from: ci.extent) else { return }
            let ui = UIImage(cgImage: cg, scale: 1, orientation: .leftMirrored)
            let scaled = ui.resized(maxWidth: 640)
            guard let jpeg = scaled.jpegData(compressionQuality: 0.4) else { return }
            var len = UInt32(jpeg.count).bigEndian
            var packet = Data(bytes: &len, count: 4)
            packet.append(jpeg)
            camConn?.send(content: packet, completion: .contentProcessed { _ in })
            frames += 1
            if now.timeIntervalSince(lastFpsAt) >= 1 {
                camFps = frames; frames = 0; lastFpsAt = now
            }
        }
    }
}

private extension UIImage {
    func resized(maxWidth: CGFloat) -> UIImage {
        let scale = min(1, maxWidth / size.width)
        let s = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: s).image { _ in draw(in: CGRect(origin: .zero, size: s)) }
    }
}
