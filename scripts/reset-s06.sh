#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

echo "=============================================================="
echo " Operation Poisoned Pipeline"
echo " S06 Behind the Firewall Reset"
echo "=============================================================="
echo

# ---------------------------------------------------------------
# PostgreSQL: recreate from pinned image, drop challenge volume
# ---------------------------------------------------------------
echo "[+] Stopping PostgreSQL..."
docker compose stop postgres >/dev/null 2>&1 || true
docker compose rm -f postgres >/dev/null 2>&1 || true

PG_VOLUME="$(
  docker volume ls \
    -q \
    --filter label=com.docker.compose.project=poisoned-pipeline \
    --filter label=com.docker.compose.volume=postgres_data \
  | head -n 1
)"

if [[ -n "${PG_VOLUME}" ]]; then
  echo "[+] Removing PostgreSQL challenge volume: ${PG_VOLUME}"
  docker volume rm "${PG_VOLUME}" >/dev/null
fi

echo "[+] Recreating PostgreSQL..."
docker compose up -d postgres

echo "[+] Waiting for PostgreSQL health..."
for attempt in $(seq 1 60); do
  STATUS="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}starting{{end}}' pp-postgres 2>/dev/null || true)"
  if [[ "${STATUS}" == "healthy" ]]; then
    echo "[+] PostgreSQL is healthy."
    break
  fi
  if [[ "${attempt}" -eq 60 ]]; then
    echo "[ERROR] PostgreSQL did not become healthy."
    docker compose logs --tail=80 postgres
    exit 1
  fi
  sleep 2
done

# ---------------------------------------------------------------
# Re-apply S06 flag and reader password
# ---------------------------------------------------------------
echo "[+] Re-seeding S06 database content..."
"${ROOT_DIR}/scripts/seed-postgres-s06.sh"

# ---------------------------------------------------------------
# Application: recreate to restore benign hook and clean state
# ---------------------------------------------------------------
echo "[+] Recreating Application Challenge container..."
docker compose up -d --force-recreate --no-deps application

echo "[+] Waiting for application healthcheck..."
for attempt in $(seq 1 30); do
  STATUS="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}starting{{end}}' pp-application 2>/dev/null || true)"
  if [[ "${STATUS}" == "healthy" ]]; then
    echo "[+] Application is healthy."
    break
  fi
  if [[ "${attempt}" -eq 30 ]]; then
    echo "[ERROR] Application did not become healthy."
    docker compose logs --tail=80 application
    exit 1
  fi
  sleep 2
done

# ---------------------------------------------------------------
# Verify
# ---------------------------------------------------------------
echo
echo "[+] Running Phase 12 verification..."
set -a
# shellcheck disable=SC1090
source private/s06/s06.env
set +a
"${ROOT_DIR}/tests/stages/verify-phase12-s06.sh"

echo
echo "=============================================================="
echo " PHASE 12 S06 RESET COMPLETE"
echo "=============================================================="