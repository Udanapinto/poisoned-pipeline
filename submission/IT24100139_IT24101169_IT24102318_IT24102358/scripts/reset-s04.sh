#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

echo "=============================================="
echo " Operation Poisoned Pipeline"
echo " S04 Poisoned Runtime Reset"
echo "=============================================="
echo

# The application container is stateless. Recreating it from the
# current pinned image restores the S04 baseline exactly, including
# the vulnerable helper, the S04 flag file, and the S05 handoff clue.

echo "[+] Recreating Application Challenge container..."
docker compose up -d --force-recreate --no-deps application

echo
echo "[+] Waiting for application healthcheck..."

for ATTEMPT in $(seq 1 30); do
  STATUS="$(docker inspect \
    --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}starting{{end}}' \
    pp-application 2>/dev/null || true)"

  if [[ "${STATUS}" == "healthy" ]]; then
    echo "[+] Application is healthy."
    break
  fi

  if [[ "${ATTEMPT}" -eq 30 ]]; then
    echo "[ERROR] Application did not become healthy."
    docker compose logs --tail=80 application
    exit 1
  fi

  sleep 2
done

echo
echo "[+] Running Phase 10 verification..."
"${ROOT_DIR}/tests/stages/verify-phase10-s04.sh"

echo
echo "=============================================="
echo " PHASE 10 S04 RESET COMPLETE"
echo "=============================================="
