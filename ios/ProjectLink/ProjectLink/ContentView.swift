import SwiftUI

struct ContentView: View {
    @ObservedObject var client = LinkClient.shared
    @State private var tab = 0

    var body: some View {
        ZStack {
            AuroraBackground()
            TabView(selection: $tab) {
                PairingView()
                    .tabItem { Label("Link", systemImage: "qrcode") }
                    .tag(0)

                TouchpadView()
                    .tabItem { Label("Pad", systemImage: "hand.draw") }
                    .tag(1)
                    .disabled(!client.isPaired)

                KeyboardView()
                    .tabItem { Label("Keys", systemImage: "keyboard") }
                    .tag(2)

                LiveScreenView()
                    .tabItem { Label("Screen", systemImage: "rectangle.connected.to.line.below") }
                    .tag(3)

                ClipboardFilesView()
                    .tabItem { Label("Share", systemImage: "square.and.arrow.up.on.square") }
                    .tag(4)

                LogsView()
                    .tabItem { Label("Logs", systemImage: "list.bullet.rectangle") }
                    .tag(5)
            }
            .tint(.cyan)
        }
    }
}

struct LogsView: View {
    @ObservedObject var client = LinkClient.shared

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Logs")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Spacer()
                Button("Clear") { client.logs.removeAll() }
                    .buttonStyle(GlowButtonStyle())
            }
            .padding(.horizontal)
            .padding(.top)

            List(client.logs, id: \.self) { line in
                Text(line)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
        }
    }
}

#Preview {
    ContentView()
}
