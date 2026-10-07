#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PRIVATE_DIR="$ROOT_DIR/private/s03"
PUBLIC_DIR="$ROOT_DIR/challenges/s03-ghost-dependency/keys"

PRIVATE_KEY="$PRIVATE_DIR/s03-signing-private.pem"
PUBLIC_KEY="$PUBLIC_DIR/s03-signing-public.pem"

mkdir -p "$PRIVATE_DIR"
mkdir -p "$PUBLIC_DIR"

umask 077

echo "=================================================="
echo " Operation Poisoned Pipeline"
echo " S03 Signing Material Generator"
echo "=================================================="
echo

if [[ ! -f "$PRIVATE_KEY" ]]; then
    echo "[+] Creating S03 signing private key."

    openssl genpkey \
        -algorithm RSA \
        -pkeyopt rsa_keygen_bits:3072 \
        -out "$PRIVATE_KEY"

    chmod 600 "$PRIVATE_KEY"
else
    echo "[+] Existing private key retained."
fi

openssl pkey \
    -in "$PRIVATE_KEY" \
    -pubout \
    -out "$PUBLIC_KEY"

chmod 644 "$PUBLIC_KEY"

echo
echo "[+] Private key:"
echo "    private/s03/s03-signing-private.pem"
echo
echo "[+] Public verification key:"
echo "    challenges/s03-ghost-dependency/keys/s03-signing-public.pem"
echo
echo "[+] No private key material displayed."
echo
echo "SUCCESS"