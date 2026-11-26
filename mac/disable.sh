#!/bin/bash
# Remote Assist - turn SSH off on macOS: remove the helper key, restore password
# settings, turn Remote Login off, drop the auto-off job and stop any tunnel.
# Optional first argument: the home folder whose key to remove (used by the timer).
TARGET_HOME="${1:-$HOME}"
AK="$TARGET_HOME/.ssh/authorized_keys"
PLIST='/Library/LaunchDaemons/com.remote-assist.autooff.plist'
SUDO=sudo; [ "$(id -u)" = 0 ] && SUDO=

if [ -f "$AK" ]; then
  grep -v ' remote-assist$' "$AK" > "$AK.tmp" || true
  cat "$AK.tmp" > "$AK" && rm -f "$AK.tmp"
fi
[ -n "$SUDO" ] && echo "macOS will ask for your login password (typing is not shown)."
$SUDO rm -f /etc/ssh/sshd_config.d/000-remote-assist.conf
$SUDO systemsetup -f -setremotelogin off >/dev/null 2>&1 || {
  $SUDO launchctl bootout system/com.openssh.sshd 2>/dev/null || true
  $SUDO launchctl disable system/com.openssh.sshd
}
$SUDO rm -rf '/Library/Application Support/RemoteAssist'
$SUDO pkill -f 'tcp@a.pinggy.io' 2>/dev/null || true
echo "Remote Assist SSH is OFF (key removed, Remote Login off)."
if [ -f "$PLIST" ]; then $SUDO rm -f "$PLIST"; $SUDO launchctl bootout system/com.remote-assist.autooff 2>/dev/null || true; fi
