#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

S01_FILE="$ROOT_DIR/private/s01/s01.env"
PRIVATE_DIR="$ROOT_DIR/private/s02"
S02_FILE="$PRIVATE_DIR/s02.env"

if [[ ! -f "$S01_FILE" ]]; then
    echo "[ERROR] Missing $S01_FILE"
    echo "Phase 6 must be completed first."
    exit 1
fi

# shellcheck disable=SC1090
source "$S01_FILE"

: "${S01_JENKINS_USER:?Missing S01_JENKINS_USER}"
: "${S01_JENKINS_PASSWORD:?Missing S01_JENKINS_PASSWORD}"
: "${S01_JOB_NAME:?Missing S01_JOB_NAME}"

mkdir -p "$PRIVATE_DIR"
umask 077

if [[ -f "$S02_FILE" ]]; then
    echo "[!] $S02_FILE already exists."
    echo "[!] Existing Phase 7 values will NOT be overwritten."
    exit 0
fi

S02_RANDOM="$(openssl rand -hex 16)"
ADMIN_PASSWORD="$(openssl rand -hex 24)"

cat > "$S02_FILE" <<EOF
# ==========================================================
# S02 - Pipeline Breach
# PRIVATE IMPLEMENTATION VALUES
# DO NOT COMMIT
# ==========================================================

JENKINS_ADMIN_USER=pp-admin
JENKINS_ADMIN_PASSWORD=${ADMIN_PASSWORD}

S02_FLAG=IE3132{PP_S02_${S02_RANDOM}}

S02_COMPROMISED_BUILD=103
S02_MANIFEST_NAME=release-manifest.txt
S02_EVIDENCE_NAME=evidence-s03.zip
EOF

chmod 600 "$S02_FILE"

echo "[+] Created private Phase 7 configuration."
echo "[+] File: private/s02/s02.env"
echo "[+] No secret values displayed."