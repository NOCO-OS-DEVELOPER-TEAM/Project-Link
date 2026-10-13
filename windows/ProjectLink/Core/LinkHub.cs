using System.Collections.Concurrent;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text.Json;

namespace ProjectLink.Core;

public sealed class LinkHub : IDisposable
{
    public string DeviceId { get; } = Guid.NewGuid().ToString("N")[..12];
    public string DeviceName { get; } = NetUtil.DeviceName();
    public byte[] PairingToken { get; private set; } = CryptoSession.CreateToken();
    public string LanIp => NetUtil.GetLanIPv4();
    public float Sensitivity { get; set; } = 1.35f;

    public bool IsPaired => _session != null && _phoneId != null;
    public string? PhoneName { get; private set; }
    public string? PhoneId => _phoneId;
    public long LastRttMs { get; private set; }
    public int InputPacketsPerSec { get; private set; }

    public event Action? StateChanged;
    public event Action<string>? Log;
    public event Action<byte[]>? PhoneFrame; // mirror of receive for UI wiring

    readonly ConcurrentQueue<string> _logs = new();
    CryptoSession? _session;
    string? _phoneId;
    TcpListener? _control;
    UdpClient? _inputUdp;
    UdpClient? _discovery;
    CancellationTokenSource? _cts;
    TcpClient? _phoneClient;
    NetworkStream? _phoneStream;
    readonly object _sendLock = new();
    int _inputCount;
    DateTime _inputWindow = DateTime.UtcNow;

    public ScreenCaptureService ScreenOut { get; }
    public ScreenReceiveService ScreenIn { get; }
    public ClipboardSyncService Clipboard { get; }
    public FileTransferService Files { get; }

    public LinkHub()
    {
        ScreenOut = new ScreenCaptureService(L);
        ScreenIn = new ScreenReceiveService(L);
        Clipboard = new ClipboardSyncService(L);
        Files = new FileTransferService(L);
        Clipboard.LocalTextChanged += async text =>
        {
            if (!IsPaired) return;
            var msg = new ClipboardMsg { Text = text, Origin = "pc", Ts = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() };
            await SendAsync(MsgType.ClipboardText, msg);
        };
        ScreenIn.FrameReceived += jpeg => PhoneFrame?.Invoke(jpeg);
    }

    void L(string m)
    {
        var line = $"[{DateTime.Now:HH:mm:ss}] {m}";
        _logs.Enqueue(line);
        while (_logs.Count > 500) _logs.TryDequeue(out _);
        Log?.Invoke(line);
    }

    public IEnumerable<string> GetLogs() => _logs.ToArray();

    public void RotateToken()
    {
        PairingToken = CryptoSession.CreateToken();
        L("Pairing token rotated");
        StateChanged?.Invoke();
    }

    public string BuildQrPayload()
    {
        var p = new PairingPayload
        {
            V = 1,
            N = DeviceName,
            Ip = LanIp,
            P = Ports.Control,
            T = CryptoSession.ToB64Url(PairingToken),
            Id = DeviceId
        };
        return JsonSerializer.Serialize(p, FrameCodec.JsonOpts);
    }

    public async Task StartAsync()
    {
        _cts = new CancellationTokenSource();
        var ct = _cts.Token;

        _control = new TcpListener(IPAddress.Any, Ports.Control);
        _control.Start();
        L($"Control TCP :{Ports.Control} — LAN {LanIp}");

        _inputUdp = new UdpClient(Ports.InputUdp);
        L($"Input UDP :{Ports.InputUdp}");

        _discovery = new UdpClient();
        _discovery.EnableBroadcast = true;
        L($"Discovery beacon :{Ports.Discovery}");

        await ScreenOut.StartAsync();
        await ScreenIn.StartAsync();

        _ = AcceptControlLoop(ct);
        _ = InputLoop(ct);
        _ = DiscoveryLoop(ct);
        _ = LatencyLoop(ct);
        _ = StatsLoop(ct);
        StateChanged?.Invoke();
    }

    async Task AcceptControlLoop(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            try
            {
                var client = await _control!.AcceptTcpClientAsync(ct);
                client.NoDelay = true;
                L($"TCP connect from {client.Client.RemoteEndPoint}");
                _ = HandleClient(client, ct);
            }
            catch (OperationCanceledException) { break; }
            catch (Exception ex) { L($"Accept: {ex.Message}"); }
        }
    }

    async Task HandleClient(TcpClient client, CancellationToken ct)
    {
        try
        {
            await using var stream = client.GetStream();
            // Hello
            await WriteFrame(stream, FrameCodec.EncodeJson(MsgType.Hello, new HelloMsg
            {
                DeviceId = DeviceId,
                Name = DeviceName,
                Role = "pc"
            }));

            var hdr = new byte[6];
            while (!ct.IsCancellationRequested && client.Connected)
            {
                await ReadExact(stream, hdr, ct);
                var len = (int)System.Buffers.Binary.BinaryPrimitives.ReadUInt32BigEndian(hdr.AsSpan(0, 4));
                var type = (MsgType)System.Buffers.Binary.BinaryPrimitives.ReadUInt16BigEndian(hdr.AsSpan(4, 2));
                if (len < 0 || len > 16_000_000) break;
                var payload = new byte[len];
                if (len > 0) await ReadExact(stream, payload, ct);
                await Dispatch(client, stream, type, payload);
            }
        }
        catch (Exception ex) { L($"Client ended: {ex.Message}"); }
        finally
        {
            if (ReferenceEquals(client, _phoneClient))
            {
                _phoneClient = null;
                _phoneStream = null;
                _session = null;
                _phoneId = null;
                PhoneName = null;
                L("Phone disconnected");
                StateChanged?.Invoke();
            }
            try { client.Dispose(); } catch { }
        }
    }

    async Task Dispatch(TcpClient client, NetworkStream stream, MsgType type, byte[] payload)
    {
        switch (type)
        {
            case MsgType.PairRequest:
            {
                var req = FrameCodec.DecodeJson<PairRequestMsg>(payload);
                if (req == null) return;
                byte[] token;
                try { token = CryptoSession.FromB64Url(req.Token); }
                catch { await WriteFrame(stream, FrameCodec.EncodeJson(MsgType.PairReject, new { reason = "bad_token" })); return; }

                if (!CryptographicEquals(token, PairingToken))
                {
                    L($"Pair reject from {req.Name}");
                    await WriteFrame(stream, FrameCodec.EncodeJson(MsgType.PairReject, new { reason = "token_mismatch" }));
                    return;
                }

                _session = CryptoSession.FromToken(token, DeviceId, req.DeviceId);
                _phoneId = req.DeviceId;
                PhoneName = req.Name;
                _phoneClient = client;
                _phoneStream = stream;
                L($"Paired ✓ {PhoneName} ({_phoneId})");
                await WriteFrame(stream, FrameCodec.EncodeJson(MsgType.PairAccept, new
                {
                    deviceId = DeviceId,
                    name = DeviceName,
                    inputPort = Ports.InputUdp,
                    screenOut = Ports.ScreenOut,
                    screenIn = Ports.ScreenIn
                }));
                StateChanged?.Invoke();
                break;
            }
            case MsgType.Ping:
                await WriteFrame(stream, FrameCodec.Encode(MsgType.Pong, payload));
                break;
            case MsgType.LatencyProbe:
            {
                // echo timestamp
                await WriteFrame(stream, FrameCodec.Encode(MsgType.LatencyReply, payload));
                break;
            }
            case MsgType.LatencyReply:
            {
                if (payload.Length >= 8)
                {
                    var sent = BitConverter.ToInt64(payload, 0);
                    LastRttMs = Math.Max(0, (DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() - sent) / 1);
                    StateChanged?.Invoke();
                }
                break;
            }
            case MsgType.ClipboardText:
            {
                var msg = FrameCodec.DecodeJson<ClipboardMsg>(payload);
                if (msg?.Text != null)
                    Clipboard.ApplyRemote(msg.Text, msg.Origin ?? "phone");
                break;
            }
            case MsgType.StreamConfig:
            {
                var cfg = FrameCodec.DecodeJson<StreamConfigMsg>(payload);
                if (cfg != null)
                {
                    if (cfg.Direction == "pc_to_phone") ScreenOut.UpdateConfig(cfg);
                    L($"Stream config: {cfg.MaxWidth}x{cfg.MaxHeight} @{cfg.Fps}fps q={cfg.JpegQuality}");
                }
                break;
            }
            case MsgType.StreamStart:
            {
                var cfg = FrameCodec.DecodeJson<StreamConfigMsg>(payload) ?? new StreamConfigMsg();
                if (cfg.Direction == "pc_to_phone")
                {
                    ScreenOut.UpdateConfig(cfg);
                    L("PC→Phone stream requested (client should connect :47802)");
                }
                else
                {
                    L("Phone→PC stream requested (phone should connect :47803)");
                }
                break;
            }
            case MsgType.MediaKey:
            {
                var m = FrameCodec.DecodeJson<MediaKeyMsg>(payload);
                if (m?.Action != null) { InputInjector.Media(m.Action); L($"Media {m.Action}"); }
                break;
            }
            case MsgType.LaunchApp:
            {
                var m = FrameCodec.DecodeJson<LaunchAppMsg>(payload);
                if (m?.Query != null)
                {
                    var ok = AppLauncher.Launch(m.Query);
                    L($"Launch '{m.Query}' → {(ok ? "ok" : "fail")}");
                }
                break;
            }
            case MsgType.FileOffer:
            {
                var o = FrameCodec.DecodeJson<FileOfferMsg>(payload);
                if (o != null)
                {
                    Files.HandleOffer(o);
                    await WriteFrame(stream, FrameCodec.EncodeJson(MsgType.FileAccept, o));
                }
                break;
            }
            case MsgType.FileChunk:
                Files.HandleChunk(payload);
                break;
            case MsgType.FileComplete:
            {
                var o = FrameCodec.DecodeJson<FileOfferMsg>(payload);
                if (o != null) Files.HandleComplete(o);
                break;
            }
            case MsgType.FileAbort:
            {
                var o = FrameCodec.DecodeJson<FileOfferMsg>(payload);
                if (o != null) Files.HandleAbort(o.TransferId);
                break;
            }
            default:
                L($"Unhandled msg {(int)type}");
                break;
        }
    }

    async Task InputLoop(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            try
            {
                var result = await _inputUdp!.ReceiveAsync(ct);
                if (!IsPaired) continue;
                if (!InputPacket.TryParse(result.Buffer, out var pkt)) continue;
                InputInjector.Apply(in pkt, Sensitivity);
                _inputCount++;
            }
            catch (OperationCanceledException) { break; }
            catch (Exception ex) { L($"UDP input: {ex.Message}"); await Task.Delay(50, ct); }
        }
    }

    async Task DiscoveryLoop(CancellationToken ct)
    {
        var fp = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(PairingToken)[..6]);
        while (!ct.IsCancellationRequested)
        {
            try
            {
                fp = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(PairingToken)[..6]);
                var beacon = DiscoveryBeacon.Encode(DeviceId, DeviceName, Ports.Control, fp);
                await _discovery!.SendAsync(beacon, beacon.Length, new IPEndPoint(IPAddress.Broadcast, Ports.Discovery));
            }
            catch { }
            await Task.Delay(2000, ct);
        }
    }

    async Task LatencyLoop(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            await Task.Delay(2000, ct);
            if (_phoneStream == null) continue;
            try
            {
                var ts = BitConverter.GetBytes(DateTimeOffset.UtcNow.ToUnixTimeMilliseconds());
                await SendAsync(MsgType.LatencyProbe, ts);
            }
            catch { }
        }
    }

    async Task StatsLoop(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            await Task.Delay(1000, ct);
            InputPacketsPerSec = _inputCount;
            _inputCount = 0;
            if (IsPaired) StateChanged?.Invoke();
        }
    }

    public Task SendAsync(MsgType type, object obj) =>
        SendRawAsync(FrameCodec.EncodeJson(type, obj));

    public Task SendAsync(MsgType type, byte[] payload) =>
        SendRawAsync(FrameCodec.Encode(type, payload));

    async Task SendRawAsync(byte[] frame)
    {
        var s = _phoneStream;
        if (s == null) return;
        try
        {
            // serialize writes
            await Task.Run(() =>
            {
                lock (_sendLock)
                {
                    s.Write(frame);
                    s.Flush();
                }
            });
        }
        catch (Exception ex) { L($"Send fail: {ex.Message}"); }
    }

    public async Task SendFileAsync(string path)
    {
        await Files.SendFileAsync(path, async frame =>
        {
            var s = _phoneStream;
            if (s == null) throw new InvalidOperationException("not connected");
            await Task.Run(() => { lock (_sendLock) { s.Write(frame); s.Flush(); } });
        });
    }

    static async Task WriteFrame(NetworkStream s, byte[] frame)
    {
        await s.WriteAsync(frame);
        await s.FlushAsync();
    }

    static async Task ReadExact(NetworkStream s, byte[] buf, CancellationToken ct)
    {
        var o = 0;
        while (o < buf.Length)
        {
            var n = await s.ReadAsync(buf.AsMemory(o, buf.Length - o), ct);
            if (n == 0) throw new EndOfStreamException();
            o += n;
        }
    }

    static bool CryptographicEquals(byte[] a, byte[] b)
    {
        if (a.Length != b.Length) return false;
        var diff = 0;
        for (int i = 0; i < a.Length; i++) diff |= a[i] ^ b[i];
        return diff == 0;
    }

    public void Dispose()
    {
        _cts?.Cancel();
        try { _control?.Stop(); } catch { }
        _inputUdp?.Dispose();
        _discovery?.Dispose();
        ScreenOut.Dispose();
        ScreenIn.Dispose();
        Clipboard.Dispose();
        _cts?.Dispose();
    }
}
