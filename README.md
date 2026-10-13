# Project Link

Native **iPhone ↔ Windows** companion — Remote Mouse, live screen (both ways), clipboard text sync, and LAN file transfer. **No cloud.** Everything stays on your Wi‑Fi.

## Architecture (why)

| Piece | Choice | Reason |
|--------|--------|--------|
| Control channel | TCP `:47800` length-framed messages | Reliable pairing, clipboard, files, stream control |
| Mouse / keys | UDP `:47801` fixed 24-byte packets | Lowest practical LAN latency (Remote Mouse style) |
| PC → iPhone video | TCP `:47802` JPEG frames | Simple adaptive quality; works without GPU encoders |
| iPhone → PC video | TCP `:47803` + ReplayKit | Realistic iOS path; full-device needs Broadcast Extension later |
| Pairing | QR with LAN IP + 32-byte token | One-scan setup; AES-256-GCM session key via HKDF |
| Discovery | UDP broadcast `:47899` | Optional LAN beacon (`LNKD`) |
| Windows UI | WPF .NET 8 | Native desktop + GDI capture + SendInput |
| iPhone UI | SwiftUI + Network.framework | Native feel, NWConnection TCP/UDP |

## Quick start (Windows)

1. Install [.NET 8 Desktop Runtime](https://dotnet.microsoft.com/download/dotnet/8.0) (SDK if you build from source).
2. Run **Project Link** from the Desktop shortcut, or:

```powershell
dotnet run --project windows/ProjectLink -c Release
```

3. Allow firewall prompts for private networks (or run `scripts/open-firewall.ps1` as Admin).
4. Scan the QR with the iOS app (same Wi‑Fi).

Published binary (after local build):

`windows/ProjectLink/bin/Release/net8.0-windows/ProjectLink.exe`

## Quick start (iPhone)

1. Sideload the IPA from GitHub Actions / Releases with **Sideloadly**, **AltStore**, or **Scarlet** (re-signs with your Apple ID).
2. Open **Project Link** → **Scan QR Code**.
3. Use **Pad** for the touchpad, **Screen** for PC↔phone video.

### iOS clipboard reality

iOS does **not** allow silent background clipboard monitoring. Sync happens when:

- the app is foregrounded,
- you tap **Send to PC** / **Read pasteboard**,
- or you open `projectlink://clip?text=...` (Share / Shortcuts).

### iPhone screen on PC

**Mirror iPhone → PC** uses ReplayKit capture. In-app capture streams the Link session; system-wide mirroring from Control Center needs a Broadcast Upload Extension (planned). PC shows frames under **iPhone Screen**.

## Ports

`47800` TCP · `47801` UDP · `47802` TCP · `47803` TCP · `47899` UDP beacon

## Build from source

### Windows

```powershell
dotnet publish windows/ProjectLink/ProjectLink.csproj -c Release -o dist/windows
```

### iOS (macOS / CI)

```bash
cd ios/ProjectLink
xcodebuild -project ProjectLink.xcodeproj -scheme ProjectLink -configuration Release \
  -sdk iphoneos CODE_SIGNING_ALLOWED=NO build
```

GitHub Actions workflow **Build iOS IPA** uploads `ProjectLink.ipa` as an artifact and attaches it to a `build-N` release.

## Protocol

See [`shared/protocol.md`](shared/protocol.md).

## Security

- Pairing token rotates with **New QR**.
- Only hosts that present the current token are accepted.
- Stay on trusted Wi‑Fi; this is not a WAN product.

## License

MIT — built for personal LAN use.
