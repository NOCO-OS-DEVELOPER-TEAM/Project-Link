import Foundation

enum LinkPorts {
    static let control = 47800
    static let inputUdp = 47801
    static let screenOut = 47802 // PC → phone
    static let screenIn = 47803  // phone → PC
    static let discovery = 47899
}

enum MsgType: UInt16 {
    case hello = 1
    case pairRequest = 2
    case pairAccept = 3
    case pairReject = 4
    case ping = 5
    case pong = 6
    case clipboardText = 10
    case fileOffer = 20
    case fileAccept = 21
    case fileChunk = 22
    case fileComplete = 23
    case fileAbort = 24
    case streamStart = 30
    case streamStop = 31
    case streamConfig = 32
    case launchApp = 40
    case mediaKey = 41
    case typeText = 42
    case settings = 80
    case status = 50
    case latencyProbe = 70
    case latencyReply = 71
}

struct PairingPayload: Codable {
    var v: Int
    var n: String
    var ip: String
    var p: Int
    var t: String
    var id: String
}

struct HelloMsg: Codable {
    var deviceId: String
    var name: String
    var role: String
    var protocolVersion: Int?
    enum CodingKeys: String, CodingKey {
        case deviceId, name, role
        case protocolVersion = "protocol"
    }
}

struct PairRequestMsg: Codable {
    var deviceId: String
    var name: String
    var token: String
}

struct PairAcceptMsg: Codable {
    var deviceId: String
    var name: String
    var inputPort: Int?
    var screenOut: Int?
    var screenIn: Int?
}

struct ClipboardMsg: Codable {
    var text: String
    var origin: String
    var ts: Int64
}

struct StreamConfigMsg: Codable {
    var direction: String
    var maxWidth: Int
    var maxHeight: Int
    var fps: Int
    var jpegQuality: Int
    var touchAsMouse: Bool
}

struct FileOfferMsg: Codable {
    var transferId: String
    var fileName: String
    var size: Int64
    var sha256: String
}

struct MediaKeyMsg: Codable {
    var action: String
}

struct LaunchAppMsg: Codable {
    var query: String
}

struct TypeTextMsg: Codable {
    var text: String
}

struct SettingsMsg: Codable {
    var sensitivity: Float?
    var highFps: Bool?
}

enum InputFlags: UInt16 {
    case move = 1
    case leftDown = 2
    case leftUp = 4
    case rightDown = 8
    case rightUp = 16
    case middleDown = 32
    case middleUp = 64
    case wheel = 128
    case keyDown = 256
    case keyUp = 512
    case doubleClick = 1024
}

enum FrameCodec {
    static func encode(type: MsgType, payload: Data) -> Data {
        var data = Data(capacity: 6 + payload.count)
        var len = UInt32(payload.count).bigEndian
        var t = type.rawValue.bigEndian
        data.append(Data(bytes: &len, count: 4))
        data.append(Data(bytes: &t, count: 2))
        data.append(payload)
        return data
    }

    static func encodeJSON<T: Encodable>(_ type: MsgType, _ value: T) throws -> Data {
        let payload = try JSONEncoder().encode(value)
        return encode(type: type, payload: payload)
    }
}

enum InputPacket {
    static let magic: UInt32 = 0x4C4E4B31
    static let size = 24

    static func build(seq: UInt32, flags: UInt16, dx: Int16, dy: Int16, wheel: Int16 = 0, vk: UInt16 = 0, mods: UInt16 = 0) -> Data {
        var d = Data(count: size)
        d.withUnsafeMutableBytes { raw in
            guard let p = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            writeU32(p, magic)
            writeU32(p + 4, seq)
            writeU16(p + 8, flags)
            writeI16(p + 10, dx)
            writeI16(p + 12, dy)
            writeI16(p + 14, wheel)
            writeU16(p + 16, vk)
            writeU16(p + 18, mods)
        }
        return d
    }

    private static func writeU32(_ p: UnsafeMutablePointer<UInt8>, _ v: UInt32) {
        let be = v.bigEndian
        withUnsafeBytes(of: be) { p.update(from: $0.bindMemory(to: UInt8.self).baseAddress!, count: 4) }
    }
    private static func writeU16(_ p: UnsafeMutablePointer<UInt8>, _ v: UInt16) {
        let be = v.bigEndian
        withUnsafeBytes(of: be) { p.update(from: $0.bindMemory(to: UInt8.self).baseAddress!, count: 2) }
    }
    private static func writeI16(_ p: UnsafeMutablePointer<UInt8>, _ v: Int16) {
        writeU16(p, UInt16(bitPattern: v))
    }
}

enum B64URL {
    static func decode(_ s: String) -> Data? {
        var str = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while str.count % 4 != 0 { str += "=" }
        return Data(base64Encoded: str)
    }
}
