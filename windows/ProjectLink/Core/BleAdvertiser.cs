using System.Runtime.InteropServices.WindowsRuntime;
using Windows.Devices.Bluetooth.Advertisement;
using Windows.Storage.Streams;

namespace ProjectLink.Core;

/// <summary>
/// BLE advertisement carrying LAN IP+port so the iPhone can discover the PC without scanning a QR.
/// High-bandwidth streams still use Wi‑Fi — BLE is discovery/pairing assist only.
/// </summary>
public sealed class BleAdvertiser : IDisposable
{
    private BluetoothLEAdvertisementPublisher? _publisher;
    private readonly Action<string> _log;

    public BleAdvertiser(Action<string> log) => _log = log;

    public void Start(string ipv4, int port, string deviceName)
    {
        Stop();
        try
        {
            var parts = ipv4.Split('.');
            if (parts.Length != 4) throw new ArgumentException("ipv4");
            var payload = new byte[10];
            payload[0] = (byte)'L'; payload[1] = (byte)'N'; payload[2] = (byte)'K'; payload[3] = (byte)'1';
            for (int i = 0; i < 4; i++) payload[4 + i] = byte.Parse(parts[i]);
            payload[8] = (byte)((port >> 8) & 0xff);
            payload[9] = (byte)(port & 0xff);

            var writer = new DataWriter();
            writer.WriteBytes(payload);
            var section = new BluetoothLEManufacturerData
            {
                CompanyId = 0xFFFF, // prototype / local use
                Data = writer.DetachBuffer()
            };

            var adv = new BluetoothLEAdvertisement();
            adv.LocalName = "ProjectLink";
            adv.ManufacturerData.Add(section);

            _publisher = new BluetoothLEAdvertisementPublisher(adv);
            _publisher.Start();
            _log($"BLE advertise ProjectLink → {ipv4}:{port}");
        }
        catch (Exception ex)
        {
            _log($"BLE advertise unavailable: {ex.Message} (Wi‑Fi QR / UDP discovery still work)");
        }
    }

    public void Stop()
    {
        try { _publisher?.Stop(); } catch { }
        _publisher = null;
    }

    public void Dispose() => Stop();
}
