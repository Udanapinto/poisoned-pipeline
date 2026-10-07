#!/bin/sh
set -eu

echo "=========================================="
echo " Operation Poisoned Pipeline"
echo " Kali Participant Environment"
echo "=========================================="

echo "[+] Network interfaces:"
ip addr show | grep -E '^[0-9]+:|inet '

echo ""
echo "[+] Default route:"
ip route

echo ""
echo "[+] Participant tools available:"
for tool in git curl jq python3 nmap proxychains4 ssh psql nc sshpass; do
    if command -v "$tool" >/dev/null 2>&1; then
        echo "    [PASS] $tool"
    else
        echo "    [FAIL] $tool"
    fi
done

echo ""
echo "[+] Kali participant ready."
echo "[+] You are on player_net only. No direct access to control_net or internal_net."

exec sleep infinity
