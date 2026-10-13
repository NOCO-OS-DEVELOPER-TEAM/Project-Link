import SwiftUI

struct KeyboardView: View {
    @ObservedObject var client = LinkClient.shared
    @State private var text = ""
    @State private var launch = ""

    // Common Windows VKs
    private let specials: [(String, UInt16, UInt16)] = [
        ("Esc", 0x1B, 0),
        ("Tab", 0x09, 0),
        ("Enter", 0x0D, 0),
        ("Back", 0x08, 0),
        ("Del", 0x2E, 0),
        ("Win", 0x5B, 0),
        ("Ctrl+C", 0x43, 1),
        ("Ctrl+V", 0x56, 1),
        ("Ctrl+Z", 0x5A, 1),
        ("Alt+Tab", 0x09, 4),
        ("Ctrl+Shift+Esc", 0x1B, 3),
        ("Win+D", 0x44, 8),
        ("F5", 0x74, 0),
        ("←", 0x25, 0),
        ("↑", 0x26, 0),
        ("↓", 0x28, 0),
        ("→", 0x27, 0),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Keyboard")
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                TextField("Type and send as key events…", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.send)
                    .onSubmit { flushText() }

                Button("Send text") { flushText() }
                    .buttonStyle(GlowButtonStyle())

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                    ForEach(specials, id: \.0) { item in
                        Button(item.0) {
                            client.key(item.1, down: true, mods: item.2)
                            client.key(item.1, down: false, mods: item.2)
                        }
                        .buttonStyle(GlowButtonStyle())
                    }
                }

                Divider().overlay(Color.white.opacity(0.15))

                Text("Launch on PC")
                    .font(.headline)
                    .foregroundStyle(.white)
                HStack {
                    TextField("notepad / chrome / spotify", text: $launch)
                        .textFieldStyle(.roundedBorder)
                    Button("Go") {
                        client.launch(launch)
                    }
                    .buttonStyle(GlowButtonStyle())
                }
            }
            .padding(16)
        }
    }

    private func flushText() {
        // Send printable ASCII as VK where possible; else clipboard paste path
        for ch in text {
            if let scalar = ch.unicodeScalars.first, scalar.isASCII {
                let vk = UInt16(vkFromASCII(UInt8(scalar.value)))
                if vk != 0 {
                    let shift: UInt16 = needsShift(UInt8(scalar.value)) ? 2 : 0
                    client.key(vk, down: true, mods: shift)
                    client.key(vk, down: false, mods: shift)
                }
            }
        }
        text = ""
    }

    private func vkFromASCII(_ c: UInt8) -> UInt8 {
        let upper = Character(UnicodeScalar(c)).uppercased().utf8.first ?? c
        switch upper {
        case 0x30...0x39, 0x41...0x5A: return upper
        case 0x20: return 0x20
        default: return 0
        }
    }

    private func needsShift(_ c: UInt8) -> Bool {
        let s = Character(UnicodeScalar(c))
        return s.isUppercase || "!@#$%^&*()_+{}|:\"<>?".contains(s)
    }
}
