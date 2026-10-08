#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

CERT_DIR="nginx/certs"
CERT_FILE="${CERT_DIR}/ctf.crt"
KEY_FILE="${CERT_DIR}/ctf.key"

echo "=================================================="
echo " Operation Poisoned Pipeline"
echo " TLS Certificate Generator"
echo "=================================================="
echo

mkdir -p "${CERT_DIR}"

if [[ -f "${CERT_FILE}" && -f "${KEY_FILE}" ]]; then
    echo "[!] TLS certificate already exists."
    echo "    Certificate: ${CERT_FILE}"
    echo "    Private key: ${KEY_FILE}"
    echo
    echo "[!] Existing certificate will NOT be overwritten."
    echo
    echo "    To force regeneration, delete both files first:"
    echo "        rm -f ${CERT_FILE} ${KEY_FILE}"
    echo
    exit 0
fi

echo "[+] Generating self-signed lab certificate..."

openssl req \
    -x509 \
    -nodes \
    -newkey rsa:2048 \
    -sha256 \
    -days 365 \
    -keyout "${KEY_FILE}" \
    -out "${CERT_FILE}" \
    -subj "/C=LK/O=Nexora Technologies/OU=Operation Poisoned Pipeline/CN=ctf.local" \
    -addext "subjectAltName=DNS:ctf.local,DNS:localhost,IP:127.0.0.1,IP:10.13.10.20" \
    2>/dev/null

chmod 600 "${KEY_FILE}"
chmod 644 "${CERT_FILE}"

echo "[+] Certificate created."
echo
echo "[+] Subject and validity:"
openssl x509 -in "${CERT_FILE}" -noout -subject -issuer -dates

echo
echo "[+] Certificate files:"
echo "    ${CERT_FILE}"
echo "    ${KEY_FILE}"
echo
echo "[!] This is a self-signed certificate for lab use only."
echo "[!] Your browser will show a warning. Choose Advanced -> Proceed."
echo
echo "[+] Verify Git ignores the private key:"
git check-ignore -v "${KEY_FILE}" || echo "    (private key may not be ignored — check .gitignore)"

echo
echo "SUCCESS"
