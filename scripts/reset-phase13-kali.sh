#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

echo "=========================================="
echo " Operation Poisoned Pipeline"
echo " Phase 13 Kali Reset"
echo "=========================================="
echo

echo "[+] Recreating Kali participant container..."

docker compose up -d --force-recreate --no-deps kali

echo "[+] Waiting for Kali to be ready..."

for ATTEMPT in $(seq 1 30); do
    if docker exec pp-kali sh -lc 'command -v git >/dev/null 2>&1'; then
        echo "[+] Kali is ready."
        break
    fi
    if [[ "${ATTEMPT}" -eq 30 ]]; then
        echo "[ERROR] Kali did not become ready."
        exit 1
    fi
    sleep 2
done

echo
echo "[+] Running Phase 13 verification..."

"${ROOT_DIR}/tests/stages/verify-phase13-kali.sh"

echo
echo "=========================================="
echo " PHASE 13 KALI RESET COMPLETE"
echo "=========================================="
