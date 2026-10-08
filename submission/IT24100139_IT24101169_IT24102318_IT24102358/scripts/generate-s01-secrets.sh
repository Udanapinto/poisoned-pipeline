#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PRIVATE_DIR="$ROOT_DIR/private/s01"
SECRET_FILE="$PRIVATE_DIR/s01.env"

mkdir -p "$PRIVATE_DIR"

umask 077

echo "=================================================="
echo " Operation Poisoned Pipeline"
echo " S01 Secret Generator"
echo "=================================================="
echo

if [[ -f "$SECRET_FILE" ]]; then
    echo "[!] $SECRET_FILE already exists."
    echo "[!] Existing S01 values will NOT be overwritten."
    echo
    exit 0
fi


# --------------------------------------------------
# Generate synthetic challenge values
# --------------------------------------------------

S01_RANDOM="$(openssl rand -hex 16)"

GITEA_ADMIN_PASSWORD="$(openssl rand -hex 20)"

JENKINS_PASSWORD="$(openssl rand -hex 16)"


cat > "$SECRET_FILE" <<EOF
# ==========================================================
# S01 - The Git Leak
# PRIVATE IMPLEMENTATION VALUES
#
# DO NOT COMMIT THIS FILE
# ==========================================================

GITEA_ADMIN_USER=nexora
GITEA_ADMIN_EMAIL=nexora-admin@lab.invalid
GITEA_ADMIN_PASSWORD=$GITEA_ADMIN_PASSWORD

S01_JENKINS_USER=pipeline-reader
S01_JENKINS_PASSWORD=$JENKINS_PASSWORD
S01_JOB_NAME=nexora-release

S01_FLAG=IE3132{PP_S01_${S01_RANDOM}}
EOF


chmod 600 "$SECRET_FILE"


# --------------------------------------------------
# Create bundle-signing key pair
# --------------------------------------------------

PRIVATE_KEY="$PRIVATE_DIR/s01-signing-private.pem"

PUBLIC_KEY="$ROOT_DIR/gitea/seeds/s01-signing-public.pem"


if [[ ! -f "$PRIVATE_KEY" ]]; then

    openssl genpkey \
        -algorithm RSA \
        -pkeyopt rsa_keygen_bits:2048 \
        -out "$PRIVATE_KEY"

    chmod 600 "$PRIVATE_KEY"

fi


openssl pkey \
    -in "$PRIVATE_KEY" \
    -pubout \
    -out "$PUBLIC_KEY"


echo "[+] Created:"
echo "    $SECRET_FILE"
echo
echo "[+] Created signing key pair."
echo
echo "[+] Real S01 values remain under private/s01/"
echo "[+] Public verification key:"
echo "    gitea/seeds/s01-signing-public.pem"
echo
echo "SUCCESS"