#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

S04_FILE="private/s04/s04.env"
S05_FILE="private/s05/s05.env"
S06_FILE="private/s06/s06.env"

if [[ ! -f "${S04_FILE}" ]]; then
  echo "[ERROR] Missing ${S04_FILE}"
  echo "Run: ./scripts/generate-s04-secrets.sh"
  exit 1
fi
if [[ ! -f "${S05_FILE}" ]]; then
  echo "[ERROR] Missing ${S05_FILE}"
  echo "Run: ./scripts/generate-s05-secrets.sh"
  exit 1
fi
if [[ ! -f "${S06_FILE}" ]]; then
  echo "[ERROR] Missing ${S06_FILE}"
  echo "Run: ./scripts/generate-s06-secrets.sh"
  exit 1
fi

# shellcheck disable=SC1090
source "${S04_FILE}"
# shellcheck disable=SC1090
source "${S05_FILE}"
# shellcheck disable=SC1090
source "${S06_FILE}"

S04_STAGE="application/.s04-private"
S05_STAGE="application/.s05-private"
S06_STAGE="application/.s06-private"

rm -rf "${S04_STAGE}" "${S05_STAGE}" "${S06_STAGE}"
mkdir -p "${S04_STAGE}" "${S05_STAGE}" "${S06_STAGE}"

# --- Phase 10 private material ---
printf '%s' "${S04_FLAG}" > "${S04_STAGE}/s04_flag.txt"
printf '%s' "${S05_HANDOFF_UTILITY}" > "${S04_STAGE}/s05_handoff.txt"

# --- Phase 11 private material ---
printf '%s' "${S05_FLAG}" > "${S05_STAGE}/s05_flag.txt"
cat > "${S05_STAGE}/s06_pivot.txt" <<EOF
S06_PIVOT_USER=${S06_PIVOT_USER}
S06_PIVOT_PASSWORD=${S06_PIVOT_PASSWORD}
EOF

# --- Phase 12 private material ---
# pivot_pass.txt is a CRYPT hash used by the Dockerfile to create the
# pivot user inside the image. The plaintext password remains only in
# private/s06/s06.env and inside /root/s06_pivot.txt in the container.
PIVOT_HASH="$(openssl passwd -6 -salt "$(openssl rand -hex 8)" "${S06_PIVOT_PASSWORD}")"
printf '%s' "${PIVOT_HASH}" > "${S06_STAGE}/pivot_pass.txt"

chmod 600 "${S04_STAGE}"/*.txt "${S05_STAGE}"/*.txt "${S06_STAGE}"/*.txt

cleanup() {
  rm -rf "${S04_STAGE}" "${S05_STAGE}" "${S06_STAGE}"
}
trap cleanup EXIT

echo "[+] Building application image..."
docker compose build application
echo "[+] Build complete."