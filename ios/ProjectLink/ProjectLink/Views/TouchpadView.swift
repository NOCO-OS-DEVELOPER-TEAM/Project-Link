import SwiftUI

struct TouchpadView: View {
    @ObservedObject var client = LinkClient.shared
    @State private var lastPoint: CGPoint?
    @State private var twoFingerStartY: CGFloat?
    @AppStorage("sensitivity") private var sensitivity: Double = 1.35
    @State private var landscapeLock = true

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 12) {
                HStack {
                    Text("Touchpad")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    Spacer()
                    Text(client.isPaired ? "LIVE" : "OFFLINE")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(client.isPaired ? Color.mint.opacity(0.25) : Color.orange.opacity(0.25), in: Capsule())
                        .foregroundStyle(client.isPaired ? .mint : .orange)
                }

                pad
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.black.opacity(0.45))
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(RainbowTheme.aurora, lineWidth: 1.5)
                            )
                    )

                HStack(spacing: 12) {
                    padButton("L", color: .white) {
                        client.leftDown(); client.leftUp()
                    }
                    padButton("R", color: .cyan) {
                        client.rightDown(); client.rightUp()
                    }
                    padButton("2×", color: .pink) {
                        client.doubleClick()
                    }
                }

                HStack {
                    Text("Sensitivity")
                        .foregroundStyle(RainbowTheme.textMuted)
                    Slider(value: $sensitivity, in: 0.4...3.0, step: 0.05)
                        .tint(.cyan)
                        .onChange(of: sensitivity) { v in
                            client.sensitivity = Float(v)
                        }
                    Text(String(format: "%.2f×", sensitivity))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .frame(width: 56, alignment: .trailing)
                }

                mediaRow
            }
            .padding(16)
            .onAppear { client.sensitivity = Float(sensitivity) }
        }
    }

    private var pad: some View {
        ZStack {
            Text("Swipe to move · tap to click · 2 fingers scroll")
                .foregroundStyle(RainbowTheme.textMuted)
                .padding()
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    // Approximate multi-touch via velocity magnitude heuristics is limited in SwiftUI;
                    // primary finger move:
                    if let last = lastPoint {
                        let dx = value.location.x - last.x
                        let dy = value.location.y - last.y
                        client.move(dx: dx, dy: dy)
                    }
                    lastPoint = value.location
                }
                .onEnded { value in
                    let travel = hypot(value.translation.width, value.translation.height)
                    if travel < 6 {
                        client.leftDown()
                        client.leftUp()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    lastPoint = nil
                }
        )
        .simultaneousGesture(
            MagnificationGesture().onEnded { _ in } // keep recognizer space soft
        )
        .gesture(
            // Vertical scroll with two-finger-like long drag from right edge is awkward;
            // dedicated scroll strip:
            DragGesture(minimumDistance: 8)
                .onChanged { _ in }
        )
        .overlay(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.06))
                .frame(width: 36)
                .padding(10)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if let y0 = twoFingerStartY {
                                let dy = value.location.y - y0
                                if abs(dy) > 8 {
                                    client.wheel(Int16(clamping: Int((-dy / 12).rounded())))
                                    twoFingerStartY = value.location.y
                                }
                            } else {
                                twoFingerStartY = value.location.y
                            }
                        }
                        .onEnded { _ in twoFingerStartY = nil }
                )
                .overlay(Text("↕").foregroundStyle(.white.opacity(0.4)))
        }
        .onLongPressGesture(minimumDuration: 0.45) {
            client.rightDown()
            client.rightUp()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    private func padButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var mediaRow: some View {
        HStack(spacing: 10) {
            ForEach([
                ("backward.fill", "prev"),
                ("playpause.fill", "play_pause"),
                ("forward.fill", "next"),
                ("speaker.wave.2.fill", "vol_up"),
                ("speaker.fill", "vol_down"),
                ("speaker.slash.fill", "mute")
            ], id: \.0) { icon, action in
                Button {
                    client.media(action)
                } label: {
                    Image(systemName: icon)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.08), in: Capsule())
                }
            }
        }
    }
}
