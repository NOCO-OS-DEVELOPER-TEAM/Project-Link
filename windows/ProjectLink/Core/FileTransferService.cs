using System.IO;
using System.Security.Cryptography;
using System.Text;

namespace ProjectLink.Core;

public sealed class FileTransferService
{
    private readonly Action<string> _log;
    private readonly string _inbox;
    public event Action<string, double>? Progress; // id, 0..1
    public event Action<string>? Completed;

    public FileTransferService(Action<string> log)
    {
        _log = log;
        _inbox = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "ProjectLink", "Inbox");
        Directory.CreateDirectory(_inbox);
    }

    public string Inbox => _inbox;

    public async Task SendFileAsync(string path, Func<byte[], Task> sendFrame)
    {
        var fi = new FileInfo(path);
        var id = Guid.NewGuid().ToString("N");
        var sha = Convert.ToHexString(await SHA256.HashDataAsync(File.OpenRead(path)));
        var offer = new FileOfferMsg
        {
            TransferId = id,
            FileName = fi.Name,
            Size = fi.Length,
            Sha256 = sha
        };
        await sendFrame(FrameCodec.EncodeJson(MsgType.FileOffer, offer));
        _log($"File offer → {fi.Name} ({fi.Length} bytes)");

        const int chunk = 64 * 1024;
        await using var fs = File.OpenRead(path);
        var buf = new byte[chunk];
        long sent = 0;
        int n;
        while ((n = await fs.ReadAsync(buf)) > 0)
        {
            var payload = new byte[16 + n]; // 16-char id prefix truncated
            var idBytes = Encoding.ASCII.GetBytes(id.PadRight(16)[..16]);
            idBytes.CopyTo(payload, 0);
            buf.AsSpan(0, n).CopyTo(payload.AsSpan(16));
            await sendFrame(FrameCodec.Encode(MsgType.FileChunk, payload));
            sent += n;
            Progress?.Invoke(id, (double)sent / fi.Length);
        }
        await sendFrame(FrameCodec.EncodeJson(MsgType.FileComplete, offer));
        Completed?.Invoke(id);
        _log($"File sent ✓ {fi.Name}");
    }

    readonly Dictionary<string, FileStream> _incoming = new();
    readonly Dictionary<string, FileOfferMsg> _offers = new();

    public void HandleOffer(FileOfferMsg offer)
    {
        _offers[offer.TransferId] = offer;
        var safe = string.Concat(offer.FileName.Where(c => !Path.GetInvalidFileNameChars().Contains(c)));
        if (string.IsNullOrWhiteSpace(safe)) safe = "file.bin";
        var dest = Path.Combine(_inbox, safe);
        if (File.Exists(dest))
            dest = Path.Combine(_inbox, $"{Path.GetFileNameWithoutExtension(safe)}_{DateTime.Now:HHmmss}{Path.GetExtension(safe)}");
        _incoming[offer.TransferId] = new FileStream(dest, FileMode.Create, FileAccess.Write);
        _log($"Receiving ← {safe}");
    }

    public void HandleChunk(ReadOnlySpan<byte> payload)
    {
        if (payload.Length < 16) return;
        var id = Encoding.ASCII.GetString(payload[..16]).Trim();
        if (!_incoming.TryGetValue(id, out var fs)) return;
        fs.Write(payload[16..]);
        if (_offers.TryGetValue(id, out var o) && o.Size > 0)
            Progress?.Invoke(id, (double)fs.Length / o.Size);
    }

    public void HandleComplete(FileOfferMsg offer)
    {
        if (_incoming.Remove(offer.TransferId, out var fs))
        {
            var path = fs.Name;
            fs.Dispose();
            Completed?.Invoke(offer.TransferId);
            _log($"File saved ✓ {path}");
            try
            {
                System.Diagnostics.Process.Start("explorer.exe", $"/select,\"{path}\"");
            }
            catch { }
        }
    }

    public void HandleAbort(string id)
    {
        if (_incoming.Remove(id, out var fs))
        {
            var path = fs.Name;
            fs.Dispose();
            try { File.Delete(path); } catch { }
            _log($"File abort {id}");
        }
    }
}
