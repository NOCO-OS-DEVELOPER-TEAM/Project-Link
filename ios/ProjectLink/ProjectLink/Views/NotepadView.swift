import SwiftUI

struct NotepadView: View {
    @ObservedObject var client = LinkClient.shared
    @State private var text = ""
    @State private var lastSent = ""
    @State private var syncMode: SyncMode = .liveChars
    @State private var timer: Timer?

    enum SyncMode: String, CaseIterable {
        case liveChars = "Every character"
        case everySecond = "Every second"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Notepad → PC")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    client.launch("notepad")
                } label: {
                    Label("Open Notepad", systemImage: "doc.text")
                }
                .buttonStyle(GlowButtonStyle())
            }

            Picker("Sync", selection: $syncMode) {
                ForEach(SyncMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Text("Schreib hier — Text geht live in das fokussierte PC-Fenster (Unicode).")
                .font(.footnote)
                .foregroundStyle(RainbowTheme.textMuted)

            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(RainbowTheme.aurora, lineWidth: 1)
                )
                .foregroundStyle(.white)
                .font(.body)
                .onChange(of: text) { newValue in
                    if syncMode == .liveChars { pushDelta(newValue) }
                }

            HStack {
                Button("Sync now") { forceFullSync() }
                    .buttonStyle(GlowButtonStyle())
                Button("Clear") { text = ""; lastSent = "" }
                    .buttonStyle(GlowButtonStyle())
                Spacer()
                Text("\(text.count) chars")
                    .foregroundStyle(RainbowTheme.textMuted)
                    .font(.caption)
            }
        }
        .padding(16)
        .onAppear { startSecondTimer() }
        .onDisappear { timer?.invalidate(); timer = nil }
        .onChange(of: syncMode) { _ in startSecondTimer() }
    }

    private func startSecondTimer() {
        timer?.invalidate()
        guard syncMode == .everySecond else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in forceFullSync() }
        }
    }

    private func pushDelta(_ newValue: String) {
        guard client.isPaired else { return }
        if newValue.hasPrefix(lastSent) {
            let added = String(newValue.dropFirst(lastSent.count))
            if !added.isEmpty { client.typeText(added) }
            lastSent = newValue
            return
        }
        if lastSent.hasPrefix(newValue) {
            let del = lastSent.count - newValue.count
            for _ in 0..<del {
                client.key(0x08, down: true, mods: 0)
                client.key(0x08, down: false, mods: 0)
            }
            lastSent = newValue
            return
        }
        forceFullSync()
    }

    private func forceFullSync() {
        guard client.isPaired, text != lastSent else { return }
        let common = commonPrefix(lastSent, text)
        let del = lastSent.count - common.count
        for _ in 0..<del {
            client.key(0x08, down: true, mods: 0)
            client.key(0x08, down: false, mods: 0)
        }
        let add = String(text.dropFirst(common.count))
        if !add.isEmpty { client.typeText(add) }
        lastSent = text
    }

    private func commonPrefix(_ a: String, _ b: String) -> String {
        var i = a.startIndex
        var j = b.startIndex
        while i < a.endIndex && j < b.endIndex && a[i] == b[j] {
            i = a.index(after: i)
            j = b.index(after: j)
        }
        return String(a[..<i])
    }
}
