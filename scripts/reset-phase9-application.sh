#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "=================================================="
echo " Operation Poisoned Pipeline"
echo " Phase 9 Application Reset"
echo "=================================================="
echo

echo "[+] Recreating Application Challenge container..."

docker compose up \
    -d \
    --force-recreate \
    --no-deps \
    application

echo
echo "[+] Waiting for application healthcheck..."

for ATTEMPT in $(seq 1 30)
do
    STATUS="$(
        docker inspect \
        pp-application \
        --format \
        '{{if .State.Health}}{{.State.Health.Status}}{{end}}' \
        2>/dev/null || true
    )"

    if [[ "$STATUS" == "healthy" ]]; then
        echo "[+] Application is healthy."
        break
    fi

    if [[ "$ATTEMPT" -eq 30 ]]; then
        echo "[ERROR] Application did not become healthy."
        exit 1
    fi

    sleep 2
done

echo
echo "[+] Running Phase 9 verification..."

"$ROOT_DIR/tests/stages/verify-phase9-application.sh"

echo
echo "=================================================="
echo " PHASE 9 APPLICATION RESET COMPLETE"
echo "=================================================="