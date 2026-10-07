#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

SECRET_FILE="private/s04/s04.env"

if [[ ! -f "${SECRET_FILE}" ]]; then
  echo "[ERROR] Missing ${SECRET_FILE}"
  echo "Run: ./scripts/generate-s04-secrets.sh"
  exit 1
fi

# shellcheck disable=SC1090
source "${SECRET_FILE}"

STAGING_DIR="application/.s04-private"
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"

printf '%s' "${S04_FLAG}" > "${STAGING_DIR}/s04_flag.txt"
printf '%s' "${S05_HANDOFF_UTILITY}" > "${STAGING_DIR}/s05_handoff.txt"

chmod 600 "${STAGING_DIR}"/*.txt

cleanup() {
  rm -rf "${STAGING_DIR}"
}
trap cleanup EXIT

echo "[+] Building application image..."
docker compose build application

echo "[+] Build complete."
