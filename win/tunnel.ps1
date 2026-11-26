# Remote Assist - reach this PC from another network through a Pinggy TCP tunnel.
# Run elevated AFTER enable.ps1:  irm https://daiyuanhao.github.io/remote-assist/win/tunnel.ps1 | iex
# Safety: refuses unless Remote Assist SSH is on (key only, password off, auto-off set).
# The tunnel stops when this window is closed, when SSH is turned off, or at auto-off time.
$ErrorActionPreference = 'Stop'
$SshDir = Join-Path $env:ProgramData 'ssh'
$TaskName = 'RemoteAssist-AutoOff'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Host 'Run as administrator (Win+R, paste, Ctrl+Shift+Enter).' -ForegroundColor Red; return }

function Test-Ready {
  $svc = Get-Service sshd -ErrorAction SilentlyContinue
  if (-not $svc -or $svc.Status -ne 'Running') { return $false }
  $cfg = Join-Path $SshDir 'sshd_config'
  if (-not (Test-Path $cfg) -or -not (Select-String -Path $cfg -SimpleMatch -Quiet 'PasswordAuthentication no # remote-assist')) { return $false }
  return [bool](Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)
}
if (-not (Test-Ready)) {
  Write-Host 'Remote Assist SSH is not on. Run the enable command first, then this one.' -ForegroundColor Red
  return
}

$ssh = Join-Path $env:WINDIR 'System32\OpenSSH\ssh.exe'
$keygen = Join-Path $env:WINDIR 'System32\OpenSSH\ssh-keygen.exe'
if (-not (Test-Path $ssh)) { Write-Host 'OpenSSH client (ssh.exe) is missing on this PC.' -ForegroundColor Red; return }
$fp = (& $keygen -lf (Join-Path $SshDir 'ssh_host_ed25519_key.pub')) -split ' ' | Select-Object -Index 1

# Pinggy only accepts publickey (any key). Use a throwaway key so no personal key is offered.
$tkey = Join-Path $SshDir 'remote-assist-tunnel_key'
if (-not (Test-Path $tkey)) { & $keygen -q -t ed25519 -N '""' -C remote-assist-tunnel -f $tkey | Out-Null }
icacls $tkey /inheritance:r /grant ($env:USERNAME + ':F') /grant 'SYSTEM:F' /grant 'Administrators:F' | Out-Null

# PowerShell 5.1 turns native stderr into errors under 2>&1; do not stop on them.
$ErrorActionPreference = 'Continue'
Write-Host 'Opening tunnel... keep this window open. Close it to stop the tunnel.'
while (Test-Ready) {
  & $ssh -T -p 443 -o StrictHostKeyChecking=accept-new -o BatchMode=yes -o IdentitiesOnly=yes -i $tkey -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes -R0:localhost:22 tcp@a.pinggy.io 2>&1 | ForEach-Object {
    if ("$_" -match 'tcp://([^\s:]+):(\d+)') {
      Write-Host ''
      Write-Host 'Remote Assist tunnel is ON.' -ForegroundColor Green
      Write-Host ('  user        : ' + $env:USERNAME)
      Write-Host ('  host        : ' + $Matches[1] + ':' + $Matches[2])
      Write-Host ('  fingerprint : ' + $fp)
      Write-Host '  Send these three lines to the person helping you. The address lasts up to 60 minutes.'
    } elseif ("$_" -notmatch 'post-quantum|store now, decrypt later|may need to be upgraded|openssh.com/pq') {
      Write-Host ('  [ssh] ' + "$_") -ForegroundColor DarkGray
    }
  }
  Write-Host ('  [ssh] exited with code ' + $LASTEXITCODE) -ForegroundColor DarkGray
  if (-not (Test-Ready)) { break }
  Write-Host 'Tunnel closed. Reconnecting in 5 seconds (the address will change)...' -ForegroundColor Yellow
  Start-Sleep -Seconds 5
}
Write-Host 'Remote Assist tunnel is OFF.' -ForegroundColor Green
