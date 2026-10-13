using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;

namespace ProjectLink.Core;

public static class NetUtil
{
    public static string GetLanIPv4()
    {
        try
        {
            foreach (var ni in NetworkInterface.GetAllNetworkInterfaces())
            {
                if (ni.OperationalStatus != OperationalStatus.Up) continue;
                if (ni.NetworkInterfaceType is NetworkInterfaceType.Loopback or NetworkInterfaceType.Tunnel) continue;
                var props = ni.GetIPProperties();
                foreach (var addr in props.UnicastAddresses)
                {
                    if (addr.Address.AddressFamily != AddressFamily.InterNetwork) continue;
                    var ip = addr.Address;
                    if (IPAddress.IsLoopback(ip)) continue;
                    var b = ip.GetAddressBytes();
                    // Prefer RFC1918
                    if (b[0] == 10 || (b[0] == 192 && b[1] == 168) || (b[0] == 172 && b[1] >= 16 && b[1] <= 31))
                        return ip.ToString();
                }
            }
        }
        catch { /* fall through */ }

        try
        {
            using var s = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);
            s.Connect("8.8.8.8", 65530);
            if (s.LocalEndPoint is IPEndPoint ep) return ep.Address.ToString();
        }
        catch { }

        return "127.0.0.1";
    }

    public static string DeviceName() =>
        Environment.MachineName;
}
