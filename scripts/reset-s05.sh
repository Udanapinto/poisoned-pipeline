#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

echo "=============================================="
echo " Operation Poisoned Pipeline"
echo " S05 Broken Trust Reset"
echo "=============================================="
echo

# The Application container is stateless. Recreating it from the
# current pinned image restores the S05 baseline exactly:
#   - benign initial hook
#   - correct file ownership / permissions
#   - S05 flag and S06 pivot credential in place
#   - sudoers fragment intact

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
echo "[+] Running Phase 11 verification..."
"${ROOT_DIR}/tests/stages/verify-phase11-s05.sh"

echo
echo "=============================================="
echo " PHASE 11 S05 RESET COMPLETE"
echo "=============================================="
