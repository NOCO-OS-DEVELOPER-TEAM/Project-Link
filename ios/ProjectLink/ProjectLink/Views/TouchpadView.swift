import SwiftUI

struct TouchpadView: View {
    @ObservedObject var client = LinkClient.shared
    @AppStorage("sensitivity") private var sensitivity: Double = 1.35
    @State private var showKeyboard = false
    @State private var liveText = ""
    @FocusState private var keyboardFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Touchpad")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    showKeyboard.toggle()
                    if showKeyboard {
                        liveText = ""
                        client.resetTypedBuffer()
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        keyboardFocused = showKeyboard
                    }
                } label: {
                    Label(showKeyboard ? "Hide keys" : "Keyboard", systemImage: "keyboard")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RainbowTheme.aurora.opacity(0.35), in: Capsule())
                }
                Text(client.isPaired ? "LIVE" : "OFFLINE")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(client.isPaired ? Color.mint.opacity(0.25) : Color.orange.opacity(0.25), in: Capsule())
                    .foregroundStyle(client.isPaired ? .mint : .orange)
            }

            if showKeyboard {
                // Hidden field drives system keyboard; every character goes to PC instantly
                TextField("Type to PC…", text: $liveText)
                    .textFieldStyle(.roundedBorder)
                    .focused($keyboardFocused)
                    .submitLabel(.done)
                    .onChange(of: liveText) { newValue in
                        client.sendTypedDelta(newValue)
                    }
                    .onSubmit {
                        client.typeText("\n")
                        liveText = ""
                        client.resetTypedBuffer()
                    }
            }

            ZStack {
                Text("1 finger move · tap = click · 2 fingers = right-click · 2-finger drag = scroll")
                    .font(.footnote)
                    .foregroundStyle(RainbowTheme.textMuted)
                    .multilineTextAlignment(.center)
                    .padding()
                    .allowsHitTesting(false)

                TouchPadSurface(
                    onMove: { dx, dy in client.move(dx: dx, dy: dy) },
                    onLeftClick: { client.leftDown(); client.leftUp() },
                    onRightClick: { client.rightDown(); client.rightUp() },
                    onScroll: { d in client.wheel(d) }
                )
            }
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
                padButton("L", color: .white) { client.leftDown(); client.leftUp() }
                padButton("R", color: .cyan) { client.rightDown(); client.rightUp() }
                padButton("2×", color: .pink) { client.doubleClick() }
            }

            HStack {
                Text("Sensitivity")
                    .foregroundStyle(RainbowTheme.textMuted)
                Slider(value: $sensitivity, in: 0.4...3.0, step: 0.05)
                    .tint(.cyan)
                    .onChange(of: sensitivity) { v in
                        client.sensitivity = Float(v)
                        client.syncSensitivity(Float(v))
                    }
                Text(String(format: "%.2f×", sensitivity))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .frame(width: 56, alignment: .trailing)
            }

            mediaRow
        }
        .padding(16)
        .onAppear {
            client.sensitivity = Float(sensitivity)
            client.syncSensitivity(Float(sensitivity))
            client.onRemoteSensitivity = { s in
                sensitivity = Double(s)
                client.sensitivity = s
            }
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
