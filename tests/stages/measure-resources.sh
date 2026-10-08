#!/usr/bin/env bash
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

echo "======================================================"
echo " Operation Poisoned Pipeline"
echo " Resource Measurement"
echo "======================================================"
echo

echo "[+] Container resource usage (docker stats --no-stream):"
echo

docker stats --no-stream --format \
    "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}" \
    pp-mariadb pp-redis pp-ctfd pp-gitea pp-jenkins pp-postgres pp-application pp-kali pp-nginx

echo
echo "[+] Host memory:"
free -h

echo
echo "[+] Host disk usage:"
df -h /var/lib/docker 2>/dev/null || df -h /

echo
echo "[+] Docker system usage:"
docker system df

echo
echo "[+] Resource measurement complete."
