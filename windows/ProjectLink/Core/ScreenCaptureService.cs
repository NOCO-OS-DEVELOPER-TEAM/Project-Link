using System.Buffers.Binary;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;

namespace ProjectLink.Core;

/// <summary>
/// Captures the primary display via GDI BitBlt, JPEG-encodes, streams over TCP 47802.
/// Adaptive quality based on measured frame size.
/// </summary>
public sealed class ScreenCaptureService : IDisposable
{
    private CancellationTokenSource? _cts;
    private TcpListener? _listener;
    private volatile bool _streaming;
    private StreamConfigMsg _cfg = new();
    private readonly Action<string> _log;

    public bool IsStreaming => _streaming;
    public int LastFps { get; private set; }
    public int LastJpegBytes { get; private set; }

    public ScreenCaptureService(Action<string> log) => _log = log;

    public void UpdateConfig(StreamConfigMsg cfg) => _cfg = cfg;

    public async Task StartAsync()
    {
        if (_listener != null) return;
        _cts = new CancellationTokenSource();
        _listener = new TcpListener(IPAddress.Any, Ports.ScreenOut);
        _listener.Start();
        _log($"Screen OUT listening on :{Ports.ScreenOut}");
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
                _log($"Screen client connected: {client.Client.RemoteEndPoint}");
                _ = StreamLoop(client, ct);
            }
            catch (OperationCanceledException) { break; }
            catch (Exception ex) { _log($"Screen accept: {ex.Message}"); }
        }
    }

    async Task StreamLoop(TcpClient client, CancellationToken ct)
    {
        _streaming = true;
        try
        {
            using (client)
            {
                await using var stream = client.GetStream();
                var frames = 0;
                var sw = System.Diagnostics.Stopwatch.StartNew();
                while (!ct.IsCancellationRequested && client.Connected)
                {
                    var cfg = _cfg;
                    var frameDelay = Math.Max(8, 1000 / Math.Max(1, cfg.Fps));
                    var jpeg = CaptureJpeg(cfg.MaxWidth, cfg.MaxHeight, cfg.JpegQuality);
                    if (jpeg.Length == 0)
                    {
                        await Task.Delay(frameDelay, ct);
                        continue;
                    }

                    LastJpegBytes = jpeg.Length;
                    var hdr = new byte[4];
                    BinaryPrimitives.WriteUInt32BigEndian(hdr, (uint)jpeg.Length);
                    await stream.WriteAsync(hdr, ct);
                    await stream.WriteAsync(jpeg, ct);
                    await stream.FlushAsync(ct);

                    frames++;
                    if (sw.ElapsedMilliseconds >= 1000)
                    {
                        LastFps = frames;
                        frames = 0;
                        sw.Restart();
                        if (LastJpegBytes > 180_000 && cfg.JpegQuality > 35)
                            _cfg.JpegQuality = Math.Max(35, cfg.JpegQuality - 5);
                        else if (LastJpegBytes < 60_000 && cfg.JpegQuality < 70)
                            _cfg.JpegQuality = Math.Min(70, cfg.JpegQuality + 2);
                    }

                    await Task.Delay(frameDelay, ct);
                }
            }
        }
        catch (Exception ex) { _log($"Screen stream ended: {ex.Message}"); }
        finally { _streaming = false; }
    }

    [DllImport("user32.dll")]
    static extern int GetSystemMetrics(int nIndex);

    public static byte[] CaptureJpeg(int maxW, int maxH, int quality)
    {
        var width = GetSystemMetrics(0);  // SM_CXSCREEN
        var height = GetSystemMetrics(1); // SM_CYSCREEN
        if (width <= 0 || height <= 0) { width = 1920; height = 1080; }

        using var bmp = new Bitmap(width, height, PixelFormat.Format24bppRgb);
        using (var g = Graphics.FromImage(bmp))
        {
            g.CopyFromScreen(0, 0, 0, 0, bmp.Size, CopyPixelOperation.SourceCopy);
        }

        var scale = Math.Min(1.0, Math.Min((double)maxW / bmp.Width, (double)maxH / bmp.Height));
        Bitmap send = bmp;
        Bitmap? scaled = null;
        if (scale < 0.999)
        {
            var w = Math.Max(1, (int)(bmp.Width * scale));
            var h = Math.Max(1, (int)(bmp.Height * scale));
            scaled = new Bitmap(w, h, PixelFormat.Format24bppRgb);
            using var g2 = Graphics.FromImage(scaled);
            g2.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.Bilinear;
            g2.DrawImage(bmp, 0, 0, w, h);
            send = scaled;
        }

        try
        {
            using var ms = new MemoryStream();
            var enc = ImageCodecInfo.GetImageEncoders().FirstOrDefault(c => c.FormatID == ImageFormat.Jpeg.Guid);
            if (enc == null)
            {
                send.Save(ms, ImageFormat.Jpeg);
            }
            else
            {
                var ep = new EncoderParameters(1);
                ep.Param[0] = new EncoderParameter(Encoder.Quality, (long)quality);
                send.Save(ms, enc, ep);
            }
            return ms.ToArray();
        }
        finally { scaled?.Dispose(); }
    }

    public void Dispose()
    {
        _cts?.Cancel();
        try { _listener?.Stop(); } catch { }
        _cts?.Dispose();
    }
}

/// <summary>
/// Accepts iPhone → PC JPEG stream on TCP 47803.
/// </summary>
public sealed class ScreenReceiveService : IDisposable
{
    private CancellationTokenSource? _cts;
    private TcpListener? _listener;
    private readonly Action<string> _log;
    public event Action<byte[]>? FrameReceived;
    public bool HasClient { get; private set; }
    public int LastFps { get; private set; }

    public ScreenReceiveService(Action<string> log) => _log = log;

    public async Task StartAsync()
    {
        if (_listener != null) return;
        _cts = new CancellationTokenSource();
        _listener = new TcpListener(IPAddress.Any, Ports.ScreenIn);
        _listener.Start();
        _log($"Screen IN listening on :{Ports.ScreenIn}");
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
                _log($"iPhone screen connected: {client.Client.RemoteEndPoint}");
                await ReceiveLoop(client, ct);
                HasClient = false;
            }
            catch (OperationCanceledException) { break; }
            catch (Exception ex) { HasClient = false; _log($"Screen IN: {ex.Message}"); }
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
                if (sw.ElapsedMilliseconds >= 1000)
                {
                    LastFps = frames;
                    frames = 0;
                    sw.Restart();
                }
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
