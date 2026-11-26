#!/bin/bash
# Remote Assist - reach this Mac from another network through a Pinggy TCP tunnel.
# Run AFTER enable.sh:  curl -fsSL https://daiyuanhao.github.io/remote-assist/mac/tunnel.sh | bash
# Safety: refuses unless Remote Assist SSH is on (key only, password off, auto-off set).
# The tunnel stops when this window is closed (or Ctrl+C), when SSH is turned off, or at auto-off time.
PLIST='/Library/LaunchDaemons/com.remote-assist.autooff.plist'

ready() {
  [ -f /etc/ssh/sshd_config.d/000-remote-assist.conf ] && [ -f "$PLIST" ] && nc -z -G 2 127.0.0.1 22 2>/dev/null
}
ready || { echo "Remote Assist SSH is not on. Run the enable command first, then this one."; exit 1; }
# Pinggy only accepts publickey (any key). Use a throwaway key so no personal key is offered.
TKEY="${TMPDIR:-/tmp}/remote-assist-tunnel_key"
[ -f "$TKEY" ] || ssh-keygen -q -t ed25519 -N '' -C remote-assist-tunnel -f "$TKEY"
FP=$(ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub | awk '{print $2}')

echo "Opening tunnel... keep this window open. Press Ctrl+C or close it to stop the tunnel."
while ready; do
  ssh -T -p 443 -o StrictHostKeyChecking=accept-new -o BatchMode=yes -o IdentitiesOnly=yes -i "$TKEY" -o ServerAliveInterval=30 \
      -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes -R0:localhost:22 tcp@a.pinggy.io 2>&1 </dev/null |
  while IFS= read -r line; do
    if [[ "$line" =~ tcp://([^[:space:]:]+):([0-9]+) ]]; then
      echo ""
      echo "Remote Assist tunnel is ON."
      echo "  user        : $(whoami)"
      echo "  host        : ${BASH_REMATCH[1]}:${BASH_REMATCH[2]}"
      echo "  fingerprint : $FP"
      echo "  Send these three lines to the person helping you. The address lasts up to 60 minutes."
    elif ! [[ "$line" =~ post-quantum|"store now, decrypt later"|"may need to be upgraded"|openssh.com/pq ]]; then
      echo "  [ssh] $line"
    fi
  done
  ready || break
  echo "Tunnel closed. Reconnecting in 5 seconds (the address will change)..."
  sleep 5
done
echo "Remote Assist tunnel is OFF."
