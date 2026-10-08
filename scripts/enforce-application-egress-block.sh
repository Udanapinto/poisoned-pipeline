#!/usr/bin/env bash
set -euo pipefail

CHAIN="PP_APP_EGRESS"
APP_IPS=("10.13.10.30" "10.13.20.1")
LAB_SUBNETS=("10.13.10.0/24" "10.13.20.0/24" "172.16.0.0/12" "127.0.0.0/8")

echo "Operation Poisoned Pipeline - Application Egress Block"
echo

if ! sudo iptables -L "${CHAIN}" -n >/dev/null 2>&1; then
    sudo iptables -N "${CHAIN}"
fi

sudo iptables -F "${CHAIN}"

for SUBNET in "${LAB_SUBNETS[@]}"; do
    sudo iptables -A "${CHAIN}" -d "${SUBNET}" -j RETURN
done

sudo iptables -A "${CHAIN}" -j DROP

for APP_IP in "${APP_IPS[@]}"; do
    sudo iptables -D FORWARD -s "${APP_IP}" -j "${CHAIN}" 2>/dev/null || true
    sudo iptables -I FORWARD 1 -s "${APP_IP}" -j "${CHAIN}"
done

echo "[+] Egress block applied for: ${APP_IPS[*]}"
sudo iptables -L "${CHAIN}" -n -v
