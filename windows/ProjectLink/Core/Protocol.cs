using System.Buffers.Binary;
using System.Text;
using System.Text.Json;

namespace ProjectLink.Core;

public static class Ports
{
    public const int Control = 47800;
    public const int InputUdp = 47801;
    public const int ScreenOut = 47802;   // PC → phone
    public const int ScreenIn = 47803;    // phone → PC
    public const int Discovery = 47899;
}

public enum MsgType : ushort
{
    Hello = 1,
    PairRequest = 2,
    PairAccept = 3,
    PairReject = 4,
    Ping = 5,
    Pong = 6,
    ClipboardText = 10,
    FileOffer = 20,
    FileAccept = 21,
    FileChunk = 22,
    FileComplete = 23,
    FileAbort = 24,
    StreamStart = 30,
    StreamStop = 31,
    StreamConfig = 32,
    LaunchApp = 40,
    MediaKey = 41,
    Status = 50,
    Log = 60,
    LatencyProbe = 70,
    LatencyReply = 71
}

[Flags]
public enum InputFlags : ushort
{
    None = 0,
    Move = 1 << 0,
    LeftDown = 1 << 1,
    LeftUp = 1 << 2,
    RightDown = 1 << 3,
    RightUp = 1 << 4,
    MiddleDown = 1 << 5,
    MiddleUp = 1 << 6,
    Wheel = 1 << 7,
    KeyDown = 1 << 8,
    KeyUp = 1 << 9,
    DoubleClick = 1 << 10
}

[Flags]
public enum KeyMods : ushort
{
    None = 0,
    Ctrl = 1,
    Shift = 2,
    Alt = 4,
    Win = 8
}

public static class FrameCodec
{
    public const int HeaderSize = 6; // len(4) + type(2)

    public static byte[] Encode(MsgType type, ReadOnlySpan<byte> payload)
    {
        var buf = new byte[HeaderSize + payload.Length];
        BinaryPrimitives.WriteUInt32BigEndian(buf.AsSpan(0, 4), (uint)payload.Length);
        BinaryPrimitives.WriteUInt16BigEndian(buf.AsSpan(4, 2), (ushort)type);
        payload.CopyTo(buf.AsSpan(HeaderSize));
        return buf;
    }

    public static byte[] EncodeJson(MsgType type, object obj)
    {
        var json = JsonSerializer.SerializeToUtf8Bytes(obj, JsonOpts);
        return Encode(type, json);
    }

    public static T? DecodeJson<T>(ReadOnlySpan<byte> payload) =>
        JsonSerializer.Deserialize<T>(payload, JsonOpts);

    public static readonly JsonSerializerOptions JsonOpts = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true
    };
}

public readonly struct InputPacket
{
    public const uint Magic = 0x4C4E4B31; // LNK1
    public const int Size = 24;

    public uint Seq { get; init; }
    public InputFlags Flags { get; init; }
    public short Dx { get; init; }
    public short Dy { get; init; }
    public short Wheel { get; init; }
    public ushort Vk { get; init; }
    public KeyMods Mods { get; init; }

    public static bool TryParse(ReadOnlySpan<byte> data, out InputPacket packet)
    {
        packet = default;
        if (data.Length < Size) return false;
        if (BinaryPrimitives.ReadUInt32BigEndian(data) != Magic) return false;
        packet = new InputPacket
        {
            Seq = BinaryPrimitives.ReadUInt32BigEndian(data[4..]),
            Flags = (InputFlags)BinaryPrimitives.ReadUInt16BigEndian(data[8..]),
            Dx = BinaryPrimitives.ReadInt16BigEndian(data[10..]),
            Dy = BinaryPrimitives.ReadInt16BigEndian(data[12..]),
            Wheel = BinaryPrimitives.ReadInt16BigEndian(data[14..]),
            Vk = BinaryPrimitives.ReadUInt16BigEndian(data[16..]),
            Mods = (KeyMods)BinaryPrimitives.ReadUInt16BigEndian(data[18..])
        };
        return true;
    }

    public byte[] ToBytes()
    {
        var b = new byte[Size];
        BinaryPrimitives.WriteUInt32BigEndian(b.AsSpan(0), Magic);
        BinaryPrimitives.WriteUInt32BigEndian(b.AsSpan(4), Seq);
        BinaryPrimitives.WriteUInt16BigEndian(b.AsSpan(8), (ushort)Flags);
        BinaryPrimitives.WriteInt16BigEndian(b.AsSpan(10), Dx);
        BinaryPrimitives.WriteInt16BigEndian(b.AsSpan(12), Dy);
        BinaryPrimitives.WriteInt16BigEndian(b.AsSpan(14), Wheel);
        BinaryPrimitives.WriteUInt16BigEndian(b.AsSpan(16), Vk);
        BinaryPrimitives.WriteUInt16BigEndian(b.AsSpan(18), (ushort)Mods);
        return b;
    }
}

public sealed class PairingPayload
{
    public int V { get; set; } = 1;
    public string N { get; set; } = "";
    public string Ip { get; set; } = "";
    public int P { get; set; } = Ports.Control;
    public string T { get; set; } = "";
    public string Id { get; set; } = "";
}

public sealed class HelloMsg
{
    public string DeviceId { get; set; } = "";
    public string Name { get; set; } = "";
    public string Role { get; set; } = "pc";
    public int Protocol { get; set; } = 1;
}

public sealed class PairRequestMsg
{
    public string DeviceId { get; set; } = "";
    public string Name { get; set; } = "";
    public string Token { get; set; } = "";
}

public sealed class ClipboardMsg
{
    public string Text { get; set; } = "";
    public string Origin { get; set; } = "";
    public long Ts { get; set; }
}

public sealed class StreamConfigMsg
{
    public string Direction { get; set; } = "pc_to_phone"; // or phone_to_pc
    public int MaxWidth { get; set; } = 1280;
    public int MaxHeight { get; set; } = 720;
    public int Fps { get; set; } = 30;
    public int JpegQuality { get; set; } = 55;
    public bool TouchAsMouse { get; set; } = true;
}

public sealed class FileOfferMsg
{
    public string TransferId { get; set; } = "";
    public string FileName { get; set; } = "";
    public long Size { get; set; }
    public string Sha256 { get; set; } = "";
}

public sealed class MediaKeyMsg
{
    public string Action { get; set; } = ""; // play_pause, next, prev, vol_up, vol_down, mute
}

public sealed class LaunchAppMsg
{
    public string Query { get; set; } = "";
}

public static class DiscoveryBeacon
{
    public static byte[] Encode(string deviceId, string name, int port, string tokenHash)
    {
        // LNKD | port u16 | idLen u8 | id | nameLen u8 | name | hashLen u8 | hash
        var id = Encoding.UTF8.GetBytes(deviceId);
        var nm = Encoding.UTF8.GetBytes(name);
        var hs = Encoding.UTF8.GetBytes(tokenHash);
        var buf = new byte[4 + 2 + 1 + id.Length + 1 + nm.Length + 1 + hs.Length];
        Encoding.ASCII.GetBytes("LNKD").CopyTo(buf, 0);
        BinaryPrimitives.WriteUInt16BigEndian(buf.AsSpan(4), (ushort)port);
        var o = 6;
        buf[o++] = (byte)id.Length;
        id.CopyTo(buf, o); o += id.Length;
        buf[o++] = (byte)nm.Length;
        nm.CopyTo(buf, o); o += nm.Length;
        buf[o++] = (byte)hs.Length;
        hs.CopyTo(buf, o);
        return buf;
    }
}
