import SwiftUI
import AVFoundation

struct PairingView: View {
    @ObservedObject var client = LinkClient.shared
    @State private var showScanner = false
    @State private var manualJSON = ""
    @State private var showManual = false

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("PROJECT LINK")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(RainbowTheme.aurora)
                Text("Scan the rainbow QR on your PC")
                    .foregroundStyle(RainbowTheme.textMuted)
            }
            .padding(.top, 24)

            statusCard

            Button {
                showScanner = true
            } label: {
                Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GlowButtonStyle())

            Button {
                showManual = true
            } label: {
                Label("Paste pairing JSON", systemImage: "doc.on.clipboard")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GlowButtonStyle())

            if client.state == .paired {
                Button(role: .destructive) {
                    client.disconnect()
                } label: {
                    Text("Disconnect")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GlowButtonStyle())
            }

            Spacer()
            Text("LAN only · no cloud · AES token in QR")
                .font(.caption)
                .foregroundStyle(RainbowTheme.textMuted)
        }
        .padding(22)
        .sheet(isPresented: $showScanner) {
            QRScannerView { code in
                showScanner = false
                client.connect(qrJSON: code)
            }
        }
        .sheet(isPresented: $showManual) {
            NavigationStack {
                TextEditor(text: $manualJSON)
                    .padding()
                    .navigationTitle("Pairing JSON")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Connect") {
                                showManual = false
                                client.connect(qrJSON: manualJSON)
                            }
                        }
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showManual = false }
                        }
                    }
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                Text(statusTitle)
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                if client.rttMs > 0 {
                    Text("RTT \(client.rttMs) ms")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.mint)
                }
            }
            if !client.pcName.isEmpty {
                Text(client.pcName)
                    .foregroundStyle(RainbowTheme.textMuted)
            }
            if let err = client.lastError {
                Text(err).foregroundStyle(.orange).font(.footnote)
            }
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(RainbowTheme.aurora.opacity(0.5), lineWidth: 1)
        )
    }

    private var statusTitle: String {
        switch client.state {
        case .idle: return "Not connected"
        case .connecting: return "Connecting…"
        case .paired: return "Linked"
        case .failed: return "Failed"
        }
    }

    private var statusColor: Color {
        switch client.state {
        case .idle: return .gray
        case .connecting: return .yellow
        case .paired: return .mint
        case .failed: return .orange
        }
    }
}

struct QRScannerView: UIViewControllerRepresentable {
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerVC {
        let vc = ScannerVC()
        vc.onCode = onCode
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerVC, context: Context) {}

    final class ScannerVC: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onCode: ((String) -> Void)?
        private let session = AVCaptureSession()
        private var handled = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.frame = view.bounds
            preview.videoGravity = .resizeAspectFill
            view.layer.addSublayer(preview)
            DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !handled,
                  let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let value = obj.stringValue else { return }
            handled = true
            session.stopRunning()
            onCode?(value)
        }
    }
}
