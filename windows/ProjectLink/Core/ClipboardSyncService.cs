using System.Runtime.InteropServices;
using System.Windows.Threading;

namespace ProjectLink.Core;

/// <summary>
/// Watches Windows clipboard for text changes. Loop-guarded via origin + last-hash.
/// iOS cannot poll clipboard in background — phone side is push-on-foreground / Share sheet.
/// </summary>
public sealed class ClipboardSyncService : IDisposable
{
    private readonly DispatcherTimer _timer;
    private readonly Action<string> _log;
    private string _lastHash = "";
    private string _lastPushed = "";
    private bool _enabled;
    private bool _suppress;

    public event Action<string>? LocalTextChanged;
    public bool Enabled
    {
        get => _enabled;
        set { _enabled = value; _log($"Clipboard sync {(value ? "ON" : "OFF")}"); }
    }

    public ClipboardSyncService(Action<string> log)
    {
        _log = log;
        _timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(400) };
        _timer.Tick += (_, _) => Poll();
        _timer.Start();
    }

    void Poll()
    {
        if (!_enabled || _suppress) return;
        try
        {
            if (!System.Windows.Clipboard.ContainsText()) return;
            var text = System.Windows.Clipboard.GetText();
            if (string.IsNullOrEmpty(text)) return;
            var hash = Hash(text);
            if (hash == _lastHash || text == _lastPushed) return;
            _lastHash = hash;
            LocalTextChanged?.Invoke(text);
        }
        catch (COMException)
        {
            // Clipboard busy — ignore
        }
        catch (Exception ex)
        {
            _log($"Clipboard poll: {ex.Message}");
        }
    }

    public void ApplyRemote(string text, string origin)
    {
        if (!_enabled) return;
        try
        {
            _suppress = true;
            _lastPushed = text;
            _lastHash = Hash(text);
            System.Windows.Clipboard.SetText(text);
            _log($"Clipboard ← {origin} ({text.Length} chars)");
        }
        catch (Exception ex) { _log($"Clipboard set: {ex.Message}"); }
        finally
        {
            // brief suppress to avoid echo
            Task.Delay(600).ContinueWith(_ => _suppress = false);
        }
    }

    static string Hash(string s) =>
        Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(s))[..8]);

    public void Dispose() => _timer.Stop();
}
