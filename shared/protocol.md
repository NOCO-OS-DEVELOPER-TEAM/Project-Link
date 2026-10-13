# Project Link Protocol v1

Local-only, no cloud. All traffic stays on the LAN.

## Ports
| Port  | Proto | Role |
|-------|-------|------|
| 47800 | TCP   | Control + pairing + clipboard + file meta |
| 47801 | UDP   | Ultra-low-latency input (mouse / scroll / keys) |
| 47802 | TCP   | Screen stream PC → iPhone (JPEG frames) |
| 47803 | TCP   | Screen stream iPhone → PC (JPEG frames) |
| 47899 | UDP   | Discovery beacon (broadcast / unicast reply) |

## Framing (TCP)
`[u32 BE length][u16 BE type][payload]`

## Message types
| Type | Name | Direction |
|------|------|-----------|
| 1 | Hello | both |
| 2 | PairRequest | phone→pc |
| 3 | PairAccept | pc→phone |
| 4 | PairReject | pc→phone |
| 5 | Ping / Pong | both (type 5 / 6) |
| 10 | ClipboardText | both |
| 20 | FileOffer | both |
| 21 | FileAccept | both |
| 22 | FileChunk | both |
| 23 | FileComplete / FileAbort | both |
| 30 | StreamStart / StreamStop | phone↔pc |
| 31 | StreamConfig | both |
| 40 | LaunchApp | phone→pc |
| 41 | MediaKey | phone→pc |
| 50 | Status | pc→phone |

## UDP input packet (fixed 24 bytes)
```
magic u32 = 0x4C4E4B31 ("LNK1")
seq   u32
flags u16  bit0=LMB,1=RMB,2=MMB,3=LDown,4=LUp,5=RDown,6=RUp,7=wheel,8=key
dx    i16
dy    i16
wheel i16
vk    u16
mods  u16  ctrl/shift/alt/win
```

## Pairing
QR JSON: `{"v":1,"n":"<pc>","ip":"<lan>","p":47800,"t":"<32-byte token b64url>","id":"<device-id>"}`

Session AES-256-GCM key = HKDF-SHA256(token, salt="ProjectLink-v1", info=deviceIds).

## Discovery
Beacon every 2s: `LNKD` + device-id + name + port + fingerprint hash.
