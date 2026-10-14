import ReplayKit
import Network
import CoreImage
import CoreMedia
import ImageIO
import UniformTypeIdentifiers

/// System-wide screen broadcast → PC :47803 (works while you leave Project Link).
class SampleHandler: RPBroadcastSampleHandler {
    private var connection: NWConnection?
    private var lastSend = Date.distantPast
    private let minInterval: TimeInterval = 1.0 / 30.0
    private let context = CIContext()

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        let defaults = UserDefaults(suiteName: "group.com.noco.projectlink") ?? .standard
        let host = defaults.string(forKey: "pcHost") ?? ""
        guard !host.isEmpty else {
            finishBroadcastWithError(NSError(domain: "ProjectLink", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Open Project Link, pair with PC, then start Broadcast again."
            ]))
            return
        }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: 47803, using: .tcp)
        connection = conn
        conn.start(queue: .global(qos: .userInitiated))
    }

    override func broadcastFinished() {
        connection?.cancel()
        connection = nil
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }
        let now = Date()
        guard now.timeIntervalSince(lastSend) >= minInterval else { return }
        lastSend = now
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ci = CIImage(cvPixelBuffer: pb)
        guard let cg = context.createCGImage(ci, from: ci.extent) else { return }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return }
        let opts: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.4]
        // Scale roughly via options — encode full then hope network keeps up; keep quality moderate
        CGImageDestinationAddImage(dest, cg, opts as CFDictionary)
        CGImageDestinationFinalize(dest)
        let jpeg = data as Data
        var len = UInt32(jpeg.count).bigEndian
        var packet = Data(bytes: &len, count: 4)
        packet.append(jpeg)
        connection?.send(content: packet, completion: .contentProcessed { _ in })
    }
}
