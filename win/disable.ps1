# Remote Assist - turn SSH off on Windows: remove the helper key, restore
# password settings, stop and disable sshd, drop the firewall rule, timer and tunnel.
# Optional first argument: the user profile whose key to remove (used by the timer).
$ErrorActionPreference = 'Continue'
$UserHome = if ($args.Count -and $args[0]) { $args[0] } else { $env:USERPROFILE }
$SshDir = Join-Path $env:ProgramData 'ssh'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Host 'Run as administrator (Win+R, paste, Ctrl+Shift+Enter).' -ForegroundColor Red; return }

foreach ($path in (Join-Path $SshDir 'administrators_authorized_keys'), (Join-Path $UserHome '.ssh\authorized_keys')) {
  if (Test-Path $path) {
    $keep = @(Get-Content $path | Where-Object { $_ -notmatch ' remote-assist$' })
    if ($keep.Count) { Set-Content -Path $path -Value $keep -Encoding ascii } else { Remove-Item $path -Force }
  }
}
$cfg = Join-Path $SshDir 'sshd_config'
if (Test-Path $cfg) { Set-Content -Path $cfg -Value @(Get-Content $cfg | Where-Object { $_ -notmatch '# remote-assist$' }) -Encoding ascii }
Remove-NetFirewallRule -Name 'RemoteAssist-SSH' -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName 'RemoteAssist-AutoOff' -Confirm:$false -ErrorAction SilentlyContinue
Remove-Item (Join-Path $SshDir 'remote-assist-disable.ps1') -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $SshDir 'remote-assist-tunnel_key*') -Force -ErrorAction SilentlyContinue
Write-Host 'Remote Assist SSH is OFF (key removed, service stopped and disabled).' -ForegroundColor Green
Stop-Service sshd -Force -ErrorAction SilentlyContinue
Set-Service sshd -StartupType Disabled -ErrorAction SilentlyContinue
# Stop any Pinggy tunnel started by tunnel.ps1.
Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match 'a\.pinggy\.io' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
