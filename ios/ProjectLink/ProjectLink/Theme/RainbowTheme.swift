import SwiftUI

enum RainbowTheme {
    static let deep = Color(red: 0.03, green: 0.03, blue: 0.06)
    static let panel = Color(red: 0.07, green: 0.07, blue: 0.12)
    static let textMuted = Color(red: 0.60, green: 0.60, blue: 0.72)

    static var aurora: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 1.0, green: 0.35, blue: 0.85),
                Color(red: 0.45, green: 0.25, blue: 1.0),
                Color(red: 0.0, green: 0.90, blue: 1.0),
                Color(red: 1.0, green: 0.85, blue: 0.35)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var softAurora: AngularGradient {
        AngularGradient(
            gradient: Gradient(colors: [
                .pink, .purple, .cyan, .yellow, .pink
            ]),
            center: .center
        )
    }
}

struct AuroraBackground: View {
    @State private var spin = false

    var body: some View {
        ZStack {
            RainbowTheme.deep
            Circle()
                .fill(RainbowTheme.aurora)
                .blur(radius: 80)
                .opacity(0.55)
                .offset(x: spin ? 40 : -60, y: spin ? -30 : 50)
                .frame(width: 420, height: 420)
            Circle()
                .fill(Color.cyan.opacity(0.35))
                .blur(radius: 70)
                .offset(x: spin ? -80 : 70, y: spin ? 120 : -40)
                .frame(width: 360, height: 360)
            RainbowTheme.softAurora
                .opacity(0.12)
                .blur(radius: 40)
                .rotationEffect(.degrees(spin ? 360 : 0))
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) {
                spin = true
            }
        }
    }
}

struct GlowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.08 : 0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(RainbowTheme.aurora, lineWidth: 1.2)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
