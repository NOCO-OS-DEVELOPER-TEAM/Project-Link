import SwiftUI
import ReplayKit

struct LiveScreenView: View {
    @ObservedObject var client = LinkClient.shared
    @StateObject private var receiver = PcScreenReceiver()
    @StateObject private var phoneStream = PhoneScreenStreamer()
    @StateObject private var av = AVStreamer()
    @State private var touchAsMouse = true
    @State private var lastTouch: CGPoint?
    @State private var highFps = true

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack {
                    Text("Live Screen")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    Spacer()
                    Text(receiver.connected ? "\(receiver.fps) fps" : "—")
                        .foregroundStyle(.mint)
                        .monospacedDigit()
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.black.opacity(0.5))
                    if let img = receiver.image {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .gesture(touchGesture)
                    } else {
                        VStack(spacing: 8) {
                            Text("PC → iPhone")
                                .foregroundStyle(.white)
                            Text(receiver.error ?? "Start stream to view your PC")
                                .font(.footnote)
                                .foregroundStyle(RainbowTheme.textMuted)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                    }
                }
                .frame(minHeight: 240)

                Toggle("Touch as mouse", isOn: $touchAsMouse)
                    .foregroundStyle(.white)
                    .tint(.cyan)
                Toggle("High FPS (55)", isOn: $highFps)
                    .foregroundStyle(.white)
                    .tint(.cyan)

                HStack {
                    Button("Start PC stream") {
                        guard client.isPaired else { return }
                        let cfg = StreamConfigMsg(
                            direction: "pc_to_phone",
                            maxWidth: highFps ? 1600 : 1280,
                            maxHeight: highFps ? 900 : 720,
                            fps: highFps ? 55 : 30,
                            jpegQuality: highFps ? 45 : 55,
                            touchAsMouse: touchAsMouse
                        )
                        client.requestPcStream(cfg: cfg)
                        receiver.start(host: client.host)
                    }
                    .buttonStyle(GlowButtonStyle())
                    .disabled(!client.isPaired)

                    Button("Stop") { receiver.stop() }
                        .buttonStyle(GlowButtonStyle())
                }

                Divider().overlay(Color.white.opacity(0.15))

                HStack {
                    Text("iPhone → PC (full device)")
                        .foregroundStyle(.white)
                    Spacer()
                    Text(phoneStream.streaming ? "\(phoneStream.sentFps) fps" : "idle")
                        .foregroundStyle(RainbowTheme.textMuted)
                }

                Text("Für Screen außerhalb der App: Broadcast aus dem Control Center starten (Project Link). In-App Mirror läuft weiter, solange die App offen ist.")
                    .font(.caption2)
                    .foregroundStyle(RainbowTheme.textMuted)

                BroadcastPicker()
                    .frame(height: 44)

                HStack {
                    Button(phoneStream.streaming ? "Stop in-app mirror" : "In-app mirror → PC") {
                        if phoneStream.streaming {
                            phoneStream.stop()
                        } else if client.isPaired {
                            client.persistPairingForBroadcast()
                            phoneStream.start(host: client.host)
                        }
                    }
                    .buttonStyle(GlowButtonStyle())
                    .disabled(!client.isPaired)
                }

                if let err = phoneStream.error {
                    Text(err).foregroundStyle(.orange).font(.footnote)
                }

                Divider().overlay(Color.white.opacity(0.15))

                Text("Kamera & Mikrofon → PC")
                    .font(.headline)
                    .foregroundStyle(.white)

                HStack {
                    Button(av.cameraOn ? "Stop camera" : "Camera on") {
                        if av.cameraOn { av.stopCamera() }
                        else if client.isPaired { av.startCamera(host: client.host) }
                    }
                    .buttonStyle(GlowButtonStyle())
                    .disabled(!client.isPaired)

                    Button(av.micOn ? "Stop mic" : "Mic on") {
                        if av.micOn { av.stopMic() }
                        else if client.isPaired { av.startMic(host: client.host) }
                    }
                    .buttonStyle(GlowButtonStyle())
                    .disabled(!client.isPaired)
                }

                if av.cameraOn {
                    Text("Camera \(av.camFps) fps → PC :47805")
                        .foregroundStyle(.mint)
                        .font(.caption)
                }
                if let err = av.error {
                    Text(err).foregroundStyle(.orange).font(.footnote)
                }
            }
            .padding(16)
        }
    }

    private var touchGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard touchAsMouse, client.isPaired else { return }
                if let last = lastTouch {
                    client.move(dx: value.location.x - last.x, dy: value.location.y - last.y)
                }
                lastTouch = value.location
            }
            .onEnded { value in
                guard touchAsMouse, client.isPaired else { lastTouch = nil; return }
                if hypot(value.translation.width, value.translation.height) < 6 {
                    client.leftDown(); client.leftUp()
                }
                lastTouch = nil
            }
    }
}

/// System broadcast picker — lets user share the whole iPhone screen (incl. other apps) to Project Link.
struct BroadcastPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let v = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 64, height: 44))
        v.preferredExtension = "com.noco.projectlink.Broadcast"
        v.showsMicrophoneButton = true
        return v
    }
    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
