using System.Buffers.Binary;
using System.IO;
using System.Net;
using System.Net.Sockets;

namespace ProjectLink.Core;

/// <summary>Receives iPhone camera JPEG on TCP 47805.</summary>
public sealed class CameraReceiveService : IDisposable
{
    public const int Port = 47805;
    private CancellationTokenSource? _cts;
    private TcpListener? _listener;
    private readonly Action<string> _log;
    public event Action<byte[]>? FrameReceived;
    public bool HasClient { get; private set; }
    public int LastFps { get; private set; }

    public CameraReceiveService(Action<string> log) => _log = log;

    public async Task StartAsync()
    {
        if (_listener != null) return;
        _cts = new CancellationTokenSource();
        _listener = new TcpListener(IPAddress.Any, Port);
        _listener.Start();
        _log($"Camera IN listening on :{Port}");
        _ = AcceptLoop(_cts.Token);
        await Task.CompletedTask;
    }

    async Task AcceptLoop(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            try
            {
                var client = await _listener!.AcceptTcpClientAsync(ct);
                client.NoDelay = true;
                HasClient = true;
                _log($"iPhone camera connected: {client.Client.RemoteEndPoint}");
                await ReceiveLoop(client, ct);
                HasClient = false;
            }
            catch (OperationCanceledException) { break; }
            catch (Exception ex) { HasClient = false; _log($"Camera IN: {ex.Message}"); }
        }
    }

    async Task ReceiveLoop(TcpClient client, CancellationToken ct)
    {
        using (client)
        {
            await using var stream = client.GetStream();
            var hdr = new byte[4];
            var frames = 0;
            var sw = System.Diagnostics.Stopwatch.StartNew();
            while (!ct.IsCancellationRequested && client.Connected)
            {
                await ReadExact(stream, hdr, ct);
                var len = (int)BinaryPrimitives.ReadUInt32BigEndian(hdr);
                if (len <= 0 || len > 8_000_000) break;
                var jpeg = new byte[len];
                await ReadExact(stream, jpeg, ct);
                FrameReceived?.Invoke(jpeg);
                frames++;
                if (sw.ElapsedMilliseconds >= 1000) { LastFps = frames; frames = 0; sw.Restart(); }
            }
        }
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

    public void Dispose()
    {
        _cts?.Cancel();
        try { _listener?.Stop(); } catch { }
        _cts?.Dispose();
    }
}
