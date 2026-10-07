#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CHALLENGE_DIR="$ROOT_DIR/challenges/s03-ghost-dependency"
DIST_DIR="$CHALLENGE_DIR/dist"

PRIVATE_DIR="$ROOT_DIR/private/s03"

PRIVATE_KEY="$PRIVATE_DIR/s03-signing-private.pem"
PUBLIC_KEY="$CHALLENGE_DIR/keys/s03-signing-public.pem"

ZIP="$DIST_DIR/evidence-s03.zip"
SIG="$DIST_DIR/evidence-s03.zip.sig"

BASELINE="$PRIVATE_DIR/baseline.env"

echo "=================================================="
echo " Operation Poisoned Pipeline"
echo " S03 Evidence Generator"
echo "=================================================="
echo

if [[ ! -f "$PRIVATE_KEY" ]]; then
    echo "[ERROR] Missing S03 signing private key."
    echo
    echo "Run:"
    echo "  ./scripts/generate-s03-secrets.sh"
    exit 1
fi

if [[ ! -f "$PUBLIC_KEY" ]]; then
    echo "[ERROR] Missing S03 public key."
    exit 1
fi

echo "[+] Generating deterministic forensic evidence..."

python3 \
    "$CHALLENGE_DIR/generate-evidence.py"

echo "[+] Signing evidence bundle..."

openssl dgst \
    -sha256 \
    -sign "$PRIVATE_KEY" \
    -out "$SIG" \
    "$ZIP"

chmod 644 "$SIG"

echo "[+] Verifying signature..."

openssl dgst \
    -sha256 \
    -verify "$PUBLIC_KEY" \
    -signature "$SIG" \
    "$ZIP" \
    >/dev/null

echo "[+] Signature verified."

ZIP_SHA="$(sha256sum "$ZIP" | awk '{print $1}')"
SIG_SHA="$(sha256sum "$SIG" | awk '{print $1}')"
PUB_SHA="$(sha256sum "$PUBLIC_KEY" | awk '{print $1}')"

if [[ ! -f "$BASELINE" ]]; then

    echo "[+] Creating initial private S03 baseline."

    cat > "$BASELINE" <<EOF
S03_EVIDENCE_SHA256=$ZIP_SHA
S03_SIGNATURE_SHA256=$SIG_SHA
S03_PUBLIC_KEY_SHA256=$PUB_SHA
EOF

    chmod 600 "$BASELINE"

else

    # shellcheck disable=SC1090
    source "$BASELINE"

    [[ "$ZIP_SHA" == "$S03_EVIDENCE_SHA256" ]] || {
        echo "[ERROR] Evidence ZIP changed from baseline."
        exit 1
    }

    [[ "$SIG_SHA" == "$S03_SIGNATURE_SHA256" ]] || {
        echo "[ERROR] Evidence signature changed from baseline."
        exit 1
    }

    [[ "$PUB_SHA" == "$S03_PUBLIC_KEY_SHA256" ]] || {
        echo "[ERROR] Public key changed from baseline."
        exit 1
    }

    echo "[+] Current evidence matches baseline."
fi

echo
echo "=================================================="
echo " S03 EVIDENCE GENERATION COMPLETE"
echo "=================================================="