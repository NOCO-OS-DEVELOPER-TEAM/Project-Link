import SwiftUI

struct LiveScreenView: View {
    @ObservedObject var client = LinkClient.shared
    @StateObject private var receiver = PcScreenReceiver()
    @StateObject private var phoneStream = PhoneScreenStreamer()
    @State private var touchAsMouse = true
    @State private var lastTouch: CGPoint?

    var body: some View {
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
            .frame(maxHeight: .infinity)

            Toggle("Touch as mouse", isOn: $touchAsMouse)
                .foregroundStyle(.white)
                .tint(.cyan)

            HStack {
                Button("Start PC stream") {
                    guard client.isPaired else { return }
                    client.requestPcStream()
                    receiver.start(host: client.host)
                }
                .buttonStyle(GlowButtonStyle())
                .disabled(!client.isPaired)

                Button("Stop") {
                    receiver.stop()
                }
                .buttonStyle(GlowButtonStyle())
            }

            Divider().overlay(Color.white.opacity(0.15))

            HStack {
                Text("iPhone → PC")
                    .foregroundStyle(.white)
                Spacer()
                Text(phoneStream.streaming ? "sending \(phoneStream.sentFps) fps" : "idle")
                    .foregroundStyle(RainbowTheme.textMuted)
            }

            if let err = phoneStream.error {
                Text(err).foregroundStyle(.orange).font(.footnote)
            }

            Text("Uses ReplayKit. Full-device Control Center broadcast needs a Broadcast Extension; in-app capture streams the Link UI / granted capture session.")
                .font(.caption2)
                .foregroundStyle(RainbowTheme.textMuted)

            HStack {
                Button(phoneStream.streaming ? "Stop iPhone mirror" : "Mirror iPhone → PC") {
                    if phoneStream.streaming {
                        phoneStream.stop()
                    } else if client.isPaired {
                        phoneStream.start(host: client.host)
                    }
                }
                .buttonStyle(GlowButtonStyle())
                .disabled(!client.isPaired)
            }
        }
        .padding(16)
        .onDisappear {
            // keep streams if user switches tabs? stop receiver only when leaving whole app — keep running
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
