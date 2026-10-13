import SwiftUI

@main
struct ProjectLinkApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    handle(url)
                }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                LinkClient.shared.syncClipboardOnForeground()
            }
        }
    }

    private func handle(_ url: URL) {
        // projectlink://clip?text=hello  or projectlink://pair?json=...
        guard url.scheme == "projectlink" else { return }
        if url.host == "clip" || url.host == "clipboard" {
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if let text = comps?.queryItems?.first(where: { $0.name == "text" })?.value?.removingPercentEncoding {
                LinkClient.shared.clipboardSyncEnabled = true
                LinkClient.shared.sendClipboard(text)
            }
        } else if url.host == "pair" {
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if let json = comps?.queryItems?.first(where: { $0.name == "json" })?.value?.removingPercentEncoding {
                LinkClient.shared.connect(qrJSON: json)
            }
        }
    }
}
