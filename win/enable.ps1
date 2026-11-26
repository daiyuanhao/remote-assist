# Remote Assist - enable SSH on Windows: key login only, password login off,
# turns itself off automatically after $Hours hours.
# Run elevated:  irm https://daiyuanhao.github.io/remote-assist/win/enable.ps1 | iex
$ErrorActionPreference = 'Stop'
$Site = 'https://daiyuanhao.github.io/remote-assist'
$PubKey = 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDLqYWGYCPVL+ZH6OLpO8RxXK4n4MJfU1Vy15n2kYptRr0DoI7UW4q0+Bf5pB0t8aXNH96qvpb5j6QEXMMWjAehQn61sofvVGOiRbFG2FgwPl+yxEMjt3TAGuoSq+81ctxyrrARBgdwOn78VUAEpNTO0Jdzqqt2txUg56QUU/03azR0DYwmC4gHKAJlM0fER3bG04PhK0m9SJjkS80ncFxfp5ItlZh6oZiOjaiIZ2fq72T5VF63+jWo7amuvclpD27S27njUdbjchTnU8JKJcYZ8s8S1QXcNjpdsVnZwNkPHtAkUnrvnwDOYVpkpUMpvFeQNpgpAiiZFVKUYHz9WGLuw+h9IxnCOto5Wq1MzyI+F/WAy24WaOASvuVhPZiEL4YelP66g5xr4Bcjv3NdHkI0Eu6xcuXfupzy54LxfKCHDpl2K3PIAgQqB/DIkTbEralJxmv+iO7cpw4ukjESK6Eq+fJrWubNO8Bj7fLhiVof+6c90TF9QApWrNeNiJZjCgk= remote-assist'
$Hours = 4
$SshDir = Join-Path $env:ProgramData 'ssh'
$RuleName = 'RemoteAssist-SSH'
$TaskName = 'RemoteAssist-AutoOff'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
  Write-Host 'Not running as administrator. Press Win+R, paste the command, then press Ctrl+Shift+Enter.' -ForegroundColor Red
  return
}

if (-not (Get-Service sshd -ErrorAction SilentlyContinue)) {
  Write-Host 'Installing OpenSSH Server (can take a few minutes)...'
  Add-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0' | Out-Null
}
Set-Service sshd -StartupType Automatic
Start-Service sshd   # first start also creates sshd_config and host keys

# Password login off. sshd uses the first value it reads, so the block goes on top.
$cfg = Join-Path $SshDir 'sshd_config'
$body = @(Get-Content $cfg | Where-Object { $_ -notmatch '# remote-assist$' })
$block = @('PasswordAuthentication no # remote-assist', 'KbdInteractiveAuthentication no # remote-assist')
Set-Content -Path $cfg -Value ($block + $body) -Encoding ascii
Restart-Service sshd

if (-not (Get-NetFirewallRule -Name $RuleName -ErrorAction SilentlyContinue)) {
  New-NetFirewallRule -Name $RuleName -DisplayName 'Remote Assist SSH (TCP 22)' -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow -Profile Any | Out-Null
}

function Add-Key([string]$path, [bool]$adminFile) {
  $dir = Split-Path $path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $lines = @(); if (Test-Path $path) { $lines = @(Get-Content $path) }
  if ($lines -notcontains $PubKey) { Add-Content -Path $path -Value $PubKey -Encoding ascii }
  if ($adminFile) { icacls $path /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F' | Out-Null }
}
Add-Key (Join-Path $SshDir 'administrators_authorized_keys') $true
Add-Key (Join-Path $env:USERPROFILE '.ssh\authorized_keys') $false

# Auto off: a one-shot SYSTEM task runs the disable script later.
$autoOff = 'not scheduled'
try {
  $off = Join-Path $SshDir 'remote-assist-disable.ps1'
  Invoke-WebRequest -UseBasicParsing -Uri ($Site + '/win/disable.ps1') -OutFile $off
  $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -ExecutionPolicy Bypass -File "' + $off + '" "' + $env:USERPROFILE + '"')
  $at = (Get-Date).AddHours($Hours)
  Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger (New-ScheduledTaskTrigger -Once -At $at) -User 'SYSTEM' -RunLevel Highest -Force | Out-Null
  $autoOff = $at.ToString('yyyy-MM-dd HH:mm')
} catch { Write-Host ('Auto off could not be scheduled: ' + $_.Exception.Message) -ForegroundColor Yellow }

$keygen = Join-Path $env:WINDIR 'System32\OpenSSH\ssh-keygen.exe'
$fp = (& $keygen -lf (Join-Path $SshDir 'ssh_host_ed25519_key.pub')) -split ' ' | Select-Object -Index 1
$ips = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' }).IPAddress
Write-Host ''
Write-Host 'Remote Assist SSH is ON (key only, password login off).' -ForegroundColor Green
Write-Host ('  user        : ' + $env:USERNAME)
Write-Host ('  host        : ' + ($ips -join ', '))
Write-Host ('  fingerprint : ' + $fp)
Write-Host ('  auto off at : ' + $autoOff)
Write-Host '  Send the user, host and fingerprint lines to the person helping you.'
