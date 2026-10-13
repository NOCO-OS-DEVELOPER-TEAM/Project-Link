using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Microsoft.Win32;
using ProjectLink.Core;
using QRCoder;
using Color = System.Windows.Media.Color;
using MessageBox = System.Windows.MessageBox;

namespace ProjectLink;

public partial class MainWindow : Window
{
    LinkHub? _hub;
    readonly DispatcherTimer _uiTimer = new() { Interval = TimeSpan.FromMilliseconds(500) };
    BitmapImage? _qrBmp;

    public MainWindow()
    {
        InitializeComponent();
        _uiTimer.Tick += (_, _) => RefreshStats();
    }

    async void Window_Loaded(object sender, RoutedEventArgs e)
    {
        if (FindResource("RainbowSpin") is Storyboard sb)
            sb.Begin();

        _hub = new LinkHub();
        _hub.Log += line => Dispatcher.Invoke(() =>
        {
            LogList.Items.Insert(0, line);
            if (LogList.Items.Count > 400) LogList.Items.RemoveAt(LogList.Items.Count - 1);
        });
        _hub.StateChanged += () => Dispatcher.Invoke(RefreshStatus);
        _hub.PhoneFrame += jpeg => Dispatcher.BeginInvoke(() => ShowPhoneFrame(jpeg));
        _hub.Files.Progress += (id, p) => Dispatcher.Invoke(() => FileProgress.Text = $"Transfer {id[..Math.Min(8, id.Length)]}… {(int)(p * 100)}%");
        _hub.Files.Completed += _ => Dispatcher.Invoke(() => FileProgress.Text = "Transfer complete");
        InboxPath.Text = $"Inbox: {_hub.Files.Inbox}";

        try
        {
            await _hub.StartAsync();
            RefreshQr();
            RefreshStatus();
            _uiTimer.Start();
            AutostartCheck.IsChecked = IsAutostartEnabled();
        }
        catch (Exception ex)
        {
            StatusText.Text = "Bind failed";
            MessageBox.Show(
                $"Could not start listeners. Is another Project Link instance running?\n\n{ex.Message}",
                "Project Link", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    void Window_Closing(object sender, System.ComponentModel.CancelEventArgs e)
    {
        _uiTimer.Stop();
        _hub?.Dispose();
    }

    void RefreshQr()
    {
        if (_hub == null) return;
        var payload = _hub.BuildQrPayload();
        using var gen = new QRCodeGenerator();
        using var data = gen.CreateQrCode(payload, QRCodeGenerator.ECCLevel.M);
        var qr = new PngByteQRCode(data);
        var bytes = qr.GetGraphic(8, new byte[] { 7, 7, 15 }, new byte[] { 255, 90, 245 });
        // Rainbow-ish: regenerate with dark bg / magenta modules — then overlay gradient feel via border
        using var gen2 = new QRCodeGenerator();
        using var data2 = gen2.CreateQrCode(payload, QRCodeGenerator.ECCLevel.M);
        var png = new PngByteQRCode(data2);
        bytes = png.GetGraphic(10, new byte[] { 12, 10, 24 }, new byte[] { 0, 232, 255 });

        _qrBmp = new BitmapImage();
        _qrBmp.BeginInit();
        _qrBmp.StreamSource = new MemoryStream(bytes);
        _qrBmp.CacheOption = BitmapCacheOption.OnLoad;
        _qrBmp.EndInit();
        _qrBmp.Freeze();
        QrImage.Source = _qrBmp;
        LanText.Text = $"{_hub.DeviceName} · {_hub.LanIp}:{Ports.Control}\nToken fingerprint ready — scan with Project Link iOS";
    }

    void RefreshStatus()
    {
        if (_hub == null) return;
        if (_hub.IsPaired)
        {
            StatusText.Text = $"Linked · {_hub.PhoneName}";
            StatusPill.Background = new SolidColorBrush(Color.FromArgb(0x55, 0x00, 0xE8, 0xA0));
            ConnDetail.Text = $"Paired with {_hub.PhoneName}\nID {_hub.PhoneId}";
        }
        else
        {
            StatusText.Text = "Listening";
            StatusPill.Background = new SolidColorBrush(Color.FromArgb(0x44, 0xFF, 0xFF, 0xFF));
            ConnDetail.Text = "Waiting for iPhone…\nScan the QR code";
        }
        LatencyText.Text = _hub.LastRttMs > 0 ? $"RTT {_hub.LastRttMs} ms" : "RTT —";
    }

    void RefreshStats()
    {
        if (_hub == null) return;
        InputStats.Text = $"{_hub.InputPacketsPerSec} pkt/s · sens {_hub.Sensitivity:0.00}×";
        StreamOutStats.Text = _hub.ScreenOut.IsStreaming
            ? $"{_hub.ScreenOut.LastFps} fps · {_hub.ScreenOut.LastJpegBytes / 1024} KB"
            : $"ready :{Ports.ScreenOut}";
        PhoneFpsText.Text = _hub.ScreenIn.HasClient ? $"{_hub.ScreenIn.LastFps} fps" : "";
        if (_hub.LastRttMs > 0) LatencyText.Text = $"RTT {_hub.LastRttMs} ms";
    }

    void ShowPhoneFrame(byte[] jpeg)
    {
        try
        {
            PhoneScreenHint.Visibility = Visibility.Collapsed;
            var bmp = new BitmapImage();
            bmp.BeginInit();
            bmp.StreamSource = new MemoryStream(jpeg);
            bmp.CacheOption = BitmapCacheOption.OnLoad;
            bmp.EndInit();
            bmp.Freeze();
            PhoneScreenImage.Source = bmp;
        }
        catch { /* corrupt frame */ }
    }

    void RotateToken_Click(object sender, RoutedEventArgs e)
    {
        _hub?.RotateToken();
        RefreshQr();
    }

    void CopyQr_Click(object sender, RoutedEventArgs e)
    {
        if (_hub == null) return;
        System.Windows.Clipboard.SetText(_hub.BuildQrPayload());
    }

    void SensSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (_hub == null || SensLabel == null) return;
        _hub.Sensitivity = (float)e.NewValue;
        SensLabel.Text = $"Sensitivity {e.NewValue:0.00}×";
    }

    void Tab_Checked(object sender, RoutedEventArgs e)
    {
        if (PanelDashboard == null) return;
        var tab = sender as ToggleButton;
        foreach (var t in new[] { TabDashboard, TabPhoneScreen, TabFiles, TabLogs })
            if (!ReferenceEquals(t, tab)) t.IsChecked = false;

        PanelDashboard.Visibility = TabDashboard.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
        PanelPhoneScreen.Visibility = TabPhoneScreen.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
        PanelFiles.Visibility = TabFiles.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
        PanelLogs.Visibility = TabLogs.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
    }

    void ClipToggle_Changed(object sender, RoutedEventArgs e)
    {
        if (_hub != null) _hub.Clipboard.Enabled = ClipToggle.IsChecked == true;
    }

    void Media_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button b && b.Tag is string action)
            InputInjector.Media(action);
    }

    void Launch_Click(object sender, RoutedEventArgs e)
    {
        AppLauncher.Launch(LaunchBox.Text.Trim());
    }

    async void StartPcStream_Click(object sender, RoutedEventArgs e)
    {
        if (_hub == null) return;
        var cfg = new StreamConfigMsg
        {
            Direction = "pc_to_phone",
            MaxWidth = 1280,
            MaxHeight = 720,
            Fps = 28,
            JpegQuality = 55
        };
        _hub.ScreenOut.UpdateConfig(cfg);
        await _hub.SendAsync(MsgType.StreamStart, cfg);
        MessageBox.Show("PC screen encoder is ready.\nOn iPhone, open Live Screen — it connects to port 47802.", "Project Link");
    }

    void TestCapture_Click(object sender, RoutedEventArgs e)
    {
        var jpeg = ScreenCaptureService.CaptureJpeg(960, 540, 50);
        var path = Path.Combine(Path.GetTempPath(), "projectlink-test.jpg");
        File.WriteAllBytes(path, jpeg);
        Process.Start(new ProcessStartInfo(path) { UseShellExecute = true });
    }

    async void SendFile_Click(object sender, RoutedEventArgs e)
    {
        if (_hub == null || !_hub.IsPaired)
        {
            MessageBox.Show("Pair an iPhone first.");
            return;
        }
        var dlg = new OpenFileDialog { Title = "Send to iPhone" };
        if (dlg.ShowDialog() != true) return;
        try { await _hub.SendFileAsync(dlg.FileName); }
        catch (Exception ex) { MessageBox.Show(ex.Message); }
    }

    void OpenInbox_Click(object sender, RoutedEventArgs e)
    {
        if (_hub == null) return;
        Directory.CreateDirectory(_hub.Files.Inbox);
        Process.Start("explorer.exe", _hub.Files.Inbox);
    }

    void ClearLogs_Click(object sender, RoutedEventArgs e) => LogList.Items.Clear();

    void Autostart_Changed(object sender, RoutedEventArgs e)
    {
        SetAutostart(AutostartCheck.IsChecked == true);
    }

    static string AutostartKey => @"Software\Microsoft\Windows\CurrentVersion\Run";
    static string AutostartName => "ProjectLink";

    static bool IsAutostartEnabled()
    {
        try
        {
            using var k = Registry.CurrentUser.OpenSubKey(AutostartKey, false);
            return k?.GetValue(AutostartName) != null;
        }
        catch { return false; }
    }

    static void SetAutostart(bool on)
    {
        try
        {
            using var k = Registry.CurrentUser.OpenSubKey(AutostartKey, true) ?? Registry.CurrentUser.CreateSubKey(AutostartKey);
            if (on)
            {
                var exe = Environment.ProcessPath ?? Process.GetCurrentProcess().MainModule?.FileName;
                if (exe != null) k?.SetValue(AutostartName, $"\"{exe}\"");
            }
            else k?.DeleteValue(AutostartName, false);
        }
        catch (Exception ex)
        {
            MessageBox.Show($"Autostart: {ex.Message}");
        }
    }
}
