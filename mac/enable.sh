#!/bin/bash
# Remote Assist - enable SSH (Remote Login) on macOS: key login only,
# password login off, turns itself off automatically after HOURS hours.
# Run in Terminal:  curl -fsSL https://daiyuanhao.github.io/remote-assist/mac/enable.sh | bash
set -e
SITE='https://daiyuanhao.github.io/remote-assist'
PUBKEY='ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDLqYWGYCPVL+ZH6OLpO8RxXK4n4MJfU1Vy15n2kYptRr0DoI7UW4q0+Bf5pB0t8aXNH96qvpb5j6QEXMMWjAehQn61sofvVGOiRbFG2FgwPl+yxEMjt3TAGuoSq+81ctxyrrARBgdwOn78VUAEpNTO0Jdzqqt2txUg56QUU/03azR0DYwmC4gHKAJlM0fER3bG04PhK0m9SJjkS80ncFxfp5ItlZh6oZiOjaiIZ2fq72T5VF63+jWo7amuvclpD27S27njUdbjchTnU8JKJcYZ8s8S1QXcNjpdsVnZwNkPHtAkUnrvnwDOYVpkpUMpvFeQNpgpAiiZFVKUYHz9WGLuw+h9IxnCOto5Wq1MzyI+F/WAy24WaOASvuVhPZiEL4YelP66g5xr4Bcjv3NdHkI0Eu6xcuXfupzy54LxfKCHDpl2K3PIAgQqB/DIkTbEralJxmv+iO7cpw4ukjESK6Eq+fJrWubNO8Bj7fLhiVof+6c90TF9QApWrNeNiJZjCgk= remote-assist'
HOURS=4
DIR='/Library/Application Support/RemoteAssist'
PLIST='/Library/LaunchDaemons/com.remote-assist.autooff.plist'

mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
touch "$HOME/.ssh/authorized_keys" && chmod 600 "$HOME/.ssh/authorized_keys"
grep -qxF "$PUBKEY" "$HOME/.ssh/authorized_keys" || echo "$PUBKEY" >> "$HOME/.ssh/authorized_keys"

echo "macOS will ask for your login password (typing is not shown)."
sudo -v

# Password login off. Files in sshd_config.d are read in name order and the
# first value wins, so 000- goes before the system's 100-macos.conf.
grep -q '^Include /etc/ssh/sshd_config.d/' /etc/ssh/sshd_config || { echo "This macOS is too old for Remote Assist (no sshd_config.d)."; exit 1; }
printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\n' | sudo tee /etc/ssh/sshd_config.d/000-remote-assist.conf >/dev/null

if ! sudo systemsetup -setremotelogin on >/dev/null 2>&1; then
  sudo launchctl enable system/com.openssh.sshd
  sudo launchctl bootstrap system /System/Library/LaunchDaemons/ssh.plist 2>/dev/null || true
fi

# Auto off: a one-shot launchd job runs the disable script later (survives reboot).
AUTO_OFF='not scheduled'
if sudo mkdir -p "$DIR" && sudo curl -fsSL "$SITE/mac/disable.sh" -o "$DIR/disable.sh"; then
  at=$(date -v+${HOURS}H '+%m %d %H %M')
  read -r mo dd hh mi <<<"$at"
  sudo tee "$PLIST" >/dev/null <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.remote-assist.autooff</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$DIR/disable.sh</string><string>$HOME</string></array>
  <key>StartCalendarInterval</key><dict>
    <key>Month</key><integer>$((10#$mo))</integer><key>Day</key><integer>$((10#$dd))</integer>
    <key>Hour</key><integer>$((10#$hh))</integer><key>Minute</key><integer>$((10#$mi))</integer>
  </dict>
</dict></plist>
PL
  sudo launchctl bootout system "$PLIST" 2>/dev/null || true
  sudo launchctl bootstrap system "$PLIST" && AUTO_OFF=$(date -v+${HOURS}H '+%Y-%m-%d %H:%M')
fi

sleep 1
if nc -z -G 2 127.0.0.1 22 2>/dev/null; then
  echo ""
  echo "Remote Assist SSH is ON (key only, password login off)."
  echo "  user        : $(whoami)"
  echo "  host        : $(ipconfig getifaddr en0 2>/dev/null || true) $(ipconfig getifaddr en1 2>/dev/null || true)"
  echo "  fingerprint : $(ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub | awk '{print $2}')"
  echo "  auto off at : $AUTO_OFF"
  echo "  Send the user, host and fingerprint lines to the person helping you."
else
  echo ""
  echo "Remote Login did not start. Open System Settings > General > Sharing and turn on Remote Login, then run this again."
  exit 1
fi
