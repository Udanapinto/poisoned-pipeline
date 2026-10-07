#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRIVATE_DIR="${ROOT_DIR}/private/s06"
SECRET_FILE="${PRIVATE_DIR}/s06.env"
S05_FILE="${ROOT_DIR}/private/s05/s05.env"
ENV_FILE="${ROOT_DIR}/.env"

if [[ ! -f "${S05_FILE}" ]]; then
  echo "[ERROR] Missing ${S05_FILE}"
  echo "Phase 11 must be completed first."
  exit 1
fi

# shellcheck disable=SC1090
source "${S05_FILE}"

: "${S06_PIVOT_USER:?S06_PIVOT_USER missing from s05.env}"
: "${S06_PIVOT_PASSWORD:?S06_PIVOT_PASSWORD missing from s05.env}"

mkdir -p "${PRIVATE_DIR}"
umask 077

echo "==============================================="
echo " Operation Poisoned Pipeline"
echo " S06 Behind the Firewall Secret Generator"
echo "==============================================="
echo

if [[ ! -f "${SECRET_FILE}" ]]; then
  S06_RANDOM="$(openssl rand -hex 16)"

  cat > "${SECRET_FILE}" <<EOF
# S06 - Behind the Firewall
# PRIVATE IMPLEMENTATION VALUES
# DO NOT COMMIT

S06_FLAG=IE3132{PP_S06_${S06_RANDOM}}

POSTGRES_DB=nexora_prod
POSTGRES_HOST=postgres
POSTGRES_INTERNAL_IP=10.13.20.10
POSTGRES_PORT=5432

DB_READER_USER=ctf_reader
DB_READER_PASSWORD=$(openssl rand -hex 24)

S06_PIVOT_USER=${S06_PIVOT_USER}
S06_PIVOT_PASSWORD=${S06_PIVOT_PASSWORD}
S06_PIVOT_HOST=nexora-app
S06_PIVOT_SSH_PORT=22
EOF

  chmod 600 "${SECRET_FILE}"
  echo "[+] Created private Phase 12 configuration."
  echo "[+] File: private/s06/s06.env"
else
  echo "[!] ${SECRET_FILE} already exists."
  echo "[!] Existing S06 values will NOT be overwritten."
fi

# shellcheck disable=SC1090
source "${SECRET_FILE}"

# ------------------------------------------------------------
# Always reconcile .env so Docker Compose can interpolate the
# PostgreSQL and reader values (do not overwrite existing keys).
# ------------------------------------------------------------
grep -q '^POSTGRES_IMAGE='        "${ENV_FILE}" || echo 'POSTGRES_IMAGE=postgres:16.4-bookworm'                    >> "${ENV_FILE}"
grep -q '^POSTGRES_ADMIN_PASSWORD=' "${ENV_FILE}" || echo "POSTGRES_ADMIN_PASSWORD=$(openssl rand -hex 24)"       >> "${ENV_FILE}"
grep -q '^POSTGRES_DB='           "${ENV_FILE}" || echo "POSTGRES_DB=${POSTGRES_DB}"                               >> "${ENV_FILE}"
grep -q '^DB_READER_USER='        "${ENV_FILE}" || echo "DB_READER_USER=${DB_READER_USER}"                         >> "${ENV_FILE}"
grep -q '^DB_READER_PASSWORD='    "${ENV_FILE}" || echo "DB_READER_PASSWORD=${DB_READER_PASSWORD}"                 >> "${ENV_FILE}"
chmod 600 "${ENV_FILE}"

echo "[+] .env reconciled with PostgreSQL keys."
echo "[+] No secret values displayed."
echo
echo "SUCCESS"