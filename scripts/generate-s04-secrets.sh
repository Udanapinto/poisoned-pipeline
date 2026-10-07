#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRIVATE_DIR="${ROOT_DIR}/private/s04"
SECRET_FILE="${PRIVATE_DIR}/s04.env"

mkdir -p "${PRIVATE_DIR}"
umask 077

echo "=============================================="
echo " Operation Poisoned Pipeline"
echo " S04 Secret Generator"
echo "=============================================="
echo

if [[ -f "${SECRET_FILE}" ]]; then
  echo "[!] ${SECRET_FILE} already exists."
  echo "[!] Existing Phase 10 values will NOT be overwritten."
  echo
  exit 0
fi

S04_RANDOM="$(openssl rand -hex 16)"

cat > "${SECRET_FILE}" <<EOF
# S04 - Poisoned Runtime
# PRIVATE IMPLEMENTATION VALUES
# DO NOT COMMIT

S04_FLAG=IE3132{PP_S04_${S04_RANDOM}}

S04_COMPONENT_NAME=nexora-utils
S04_COMPONENT_VERSION=2.4.1
S04_DIAGNOSTICS_PATH=/api/diagnostics/run
S04_SERVICE_ACCOUNT=pipeline-app
S04_SERVICE_UID=10001

# S05 handoff clue
S05_HANDOFF_UTILITY=deploy-verify
S05_HANDOFF_CONFIG_PATH=/opt/nexora/config/deployment.conf
S05_HANDOFF_HOOK_PATH=/opt/nexora/hooks/verify.sh

S04_AFFECTED_APP_VERSION=nexora-platform-2026.09.03
S04_TARGET_HOST=nexora-app
EOF

chmod 600 "${SECRET_FILE}"

echo "[+] Created private Phase 10 configuration."
echo "[+] File: private/s04/s04.env"
echo "[+] No secret values displayed."
echo
echo "SUCCESS"
