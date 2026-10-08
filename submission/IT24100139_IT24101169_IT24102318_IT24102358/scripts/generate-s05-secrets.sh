#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRIVATE_DIR="${ROOT_DIR}/private/s05"
SECRET_FILE="${PRIVATE_DIR}/s05.env"

mkdir -p "${PRIVATE_DIR}"
umask 077

echo "=============================================="
echo " Operation Poisoned Pipeline"
echo " S05 Broken Trust Secret Generator"
echo "=============================================="
echo

if [[ -f "${SECRET_FILE}" ]]; then
  echo "[!] ${SECRET_FILE} already exists."
  echo "[!] Existing S05 values will NOT be overwritten."
  exit 0
fi

S05_RANDOM="$(openssl rand -hex 16)"
S06_PIVOT_PASSWORD="$(openssl rand -hex 24)"

cat > "${SECRET_FILE}" <<EOF
# S05 - Broken Trust
# PRIVATE IMPLEMENTATION VALUES
# DO NOT COMMIT

S05_FLAG=IE3132{PP_S05_${S05_RANDOM}}

# S05 -> S06 handoff
S06_PIVOT_USER=pivot
S06_PIVOT_PASSWORD=${S06_PIVOT_PASSWORD}
S06_PIVOT_HOST=nexora-app
S06_PIVOT_SSH_PORT=22

# Reference values for verification
S05_UTILITY_PATH=/usr/local/bin/deploy-verify
S05_CONFIG_PATH=/opt/nexora/config/deployment.conf
S05_HOOK_PATH=/opt/nexora/hooks/verify.sh
EOF

chmod 600 "${SECRET_FILE}"

echo "[+] Created private Phase 11 configuration."
echo "[+] File: private/s05/s05.env"
echo "[+] No secret values displayed."
echo
echo "SUCCESS"
