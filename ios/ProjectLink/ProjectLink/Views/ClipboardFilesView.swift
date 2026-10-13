import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ClipboardFilesView: View {
    @ObservedObject var client = LinkClient.shared
    @AppStorage("clipboardSync") private var clipboardSync = false
    @State private var outgoing = ""
    @State private var showImporter = false
    @State private var transferNote = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Clipboard")
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                Toggle("Sync text with PC", isOn: $clipboardSync)
                    .foregroundStyle(.white)
                    .tint(.cyan)
                    .onChange(of: clipboardSync) { v in
                        client.clipboardSyncEnabled = v
                    }

                Text("iOS blocks silent background clipboard access. Sync runs when this app is active, when you tap Send, or via the Share sheet.")
                    .font(.footnote)
                    .foregroundStyle(RainbowTheme.textMuted)

                if !client.clipboardPreview.isEmpty {
                    Text("Last: \(client.clipboardPreview.prefix(120))")
                        .font(.caption)
                        .foregroundStyle(.mint)
                }

                TextField("Text to send → PC", text: $outgoing, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Send to PC") {
                        client.clipboardSyncEnabled = true
                        clipboardSync = true
                        client.sendClipboard(outgoing)
                    }
                    .buttonStyle(GlowButtonStyle())
                    .disabled(!client.isPaired || outgoing.isEmpty)

                    Button("Read pasteboard") {
                        outgoing = UIPasteboard.general.string ?? ""
                        if clipboardSync { client.sendClipboard(outgoing) }
                    }
                    .buttonStyle(GlowButtonStyle())
                }

                Divider().overlay(Color.white.opacity(0.15))

                Text("Files")
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                Text("Pick a file to send over LAN. Incoming files from PC land in the Files app Documents folder when the transfer handler is active.")
                    .font(.footnote)
                    .foregroundStyle(RainbowTheme.textMuted)

                Button("Send file to PC…") { showImporter = true }
                    .buttonStyle(GlowButtonStyle())
                    .disabled(!client.isPaired)

                if !transferNote.isEmpty {
                    Text(transferNote).foregroundStyle(.mint).font(.footnote)
                }
            }
            .padding(16)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await sendFile(url) }
            case .failure(let e):
                transferNote = e.localizedDescription
            }
        }
        .onAppear { client.clipboardSyncEnabled = clipboardSync }
    }

    private func sendFile(_ url: URL) async {
        guard client.isPaired else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16).description
            let offer = FileOfferMsg(
                transferId: id,
                fileName: url.lastPathComponent,
                size: Int64(data.count),
                sha256: ""
            )
            client.sendJSON(.fileOffer, offer)
            // wait briefly for accept — fire chunks anyway
            let chunk = 64 * 1024
            var offset = 0
            while offset < data.count {
                let end = min(offset + chunk, data.count)
                var payload = Data(id.utf8)
                if payload.count < 16 { payload.append(Data(repeating: 0x20, count: 16 - payload.count)) }
                if payload.count > 16 { payload = payload.prefix(16) }
                payload.append(data[offset..<end])
                client.sendRaw(FrameCodec.encode(type: .fileChunk, payload: payload))
                offset = end
                transferNote = "Sending… \(offset)/\(data.count)"
            }
            client.sendJSON(.fileComplete, offer)
            transferNote = "Sent \(url.lastPathComponent)"
        } catch {
            transferNote = error.localizedDescription
        }
    }
}

/// Share Extension entry helper used from Share sheet via openURL — also a simple share receiver view.
struct ShareIncomingView: View {
    let text: String
    @ObservedObject var client = LinkClient.shared

    var body: some View {
        VStack(spacing: 16) {
            Text("Share to Project Link")
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text(text)
                .foregroundStyle(RainbowTheme.textMuted)
                .padding()
            Button("Send text to PC") {
                client.clipboardSyncEnabled = true
                client.sendClipboard(text)
            }
            .buttonStyle(GlowButtonStyle())
            .disabled(!client.isPaired)
        }
        .padding()
    }
}
