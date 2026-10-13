# Run as Administrator — opens Project Link LAN ports for Private profiles
$portsTcp = 47800, 47802, 47803
$portsUdp = 47801, 47899
foreach ($p in $portsTcp) {
  New-NetFirewallRule -DisplayName "ProjectLink TCP $p" -Direction Inbound -Protocol TCP -LocalPort $p -Action Allow -Profile Private -ErrorAction SilentlyContinue | Out-Null
}
foreach ($p in $portsUdp) {
  New-NetFirewallRule -DisplayName "ProjectLink UDP $p" -Direction Inbound -Protocol UDP -LocalPort $p -Action Allow -Profile Private -ErrorAction SilentlyContinue | Out-Null
}
Write-Host "Firewall rules ensured for Project Link (Private profile)."
