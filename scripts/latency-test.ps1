# Sends UDP mouse packets to localhost and measures round-trip via TCP latency probe framing is separate.
# This script floods 500 move packets and reports send rate (injector path stress).
param([string]$HostAddr = "127.0.0.1", [int]$Count = 500)
$udp = New-Object System.Net.Sockets.UdpClient
$ep = New-Object System.Net.IPEndPoint ([System.Net.IPAddress]::Parse($HostAddr), 47801)
$sw = [System.Diagnostics.Stopwatch]::StartNew()
for ($i = 0; $i -lt $Count; $i++) {
  $buf = New-Object byte[] 24
  # magic LNK1
  $buf[0]=0x4C; $buf[1]=0x4E; $buf[2]=0x4B; $buf[3]=0x31
  $seq = [BitConverter]::GetBytes([System.Net.IPAddress]::HostToNetworkOrder([int]$i))
  [Array]::Copy($seq, 0, $buf, 4, 4)
  $buf[8]=0; $buf[9]=1 # flags MOVE big-endian 0x0001
  $buf[11]=2; $buf[13]=0 # dx=2
  $udp.Send($buf, 24, $ep) | Out-Null
}
$sw.Stop()
Write-Host ("Sent {0} packets in {1} ms ({2:n0} pkt/s)" -f $Count, $sw.ElapsedMilliseconds, ($Count / [math]::Max(0.001, $sw.Elapsed.TotalSeconds)))
$udp.Close()
