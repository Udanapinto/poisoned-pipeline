#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SECRET_FILE="$ROOT_DIR/private/s01/s01.env"

BUNDLE="$ROOT_DIR/private/s01/deployment-tools.bundle"

SIGNATURE="$ROOT_DIR/private/s01/deployment-tools.bundle.sig"

PUBLIC_KEY="$ROOT_DIR/gitea/seeds/s01-signing-public.pem"


if [[ ! -f "$SECRET_FILE" ]]; then

    echo "[ERROR] Missing S01 private configuration."
    exit 1

fi


if [[ ! -f "$BUNDLE" ]]; then

    echo "[ERROR] Missing S01 Git bundle."
    exit 1

fi


# shellcheck disable=SC1090
source "$SECRET_FILE"


# --------------------------------------------------
# Verify signed bundle
# --------------------------------------------------

echo "[+] Verifying S01 bundle signature..."

openssl dgst \
    -sha256 \
    -verify "$PUBLIC_KEY" \
    -signature "$SIGNATURE" \
    "$BUNDLE"


git bundle verify "$BUNDLE" >/dev/null


echo "[PASS] S01 bundle verified."


# --------------------------------------------------
# Create repository using Gitea API
# --------------------------------------------------

echo "[+] Creating Gitea repository..."


HTTP_CODE="$(curl \
    -ksS \
    -o /tmp/s01-gitea-create.json \
    -w '%{http_code}' \
    -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" \
    -H "Content-Type: application/json" \
    -X POST \
    -d '{
          "name": "deployment-tools",
          "description": "Nexora deployment automation tooling",
          "private": false,
          "auto_init": false
        }' \
    "https://10.13.10.20/git/api/v1/user/repos")"


if [[ "$HTTP_CODE" != "201" && "$HTTP_CODE" != "409" ]]; then

    echo "[ERROR] Repository creation failed."
    echo "HTTP status: $HTTP_CODE"
    cat /tmp/s01-gitea-create.json
    exit 1

fi


echo "[PASS] Repository exists."


# --------------------------------------------------
# Prepare temporary mirror
# --------------------------------------------------

WORK_DIR="$(mktemp -d)"

cleanup() {

    rm -rf "$WORK_DIR"

}

trap cleanup EXIT


git clone \
    --mirror \
    "$BUNDLE" \
    "$WORK_DIR/deployment-tools.git" \
    >/dev/null 2>&1


cd "$WORK_DIR/deployment-tools.git"


# --------------------------------------------------
# Temporary Git AskPass helper
# --------------------------------------------------

ASKPASS="$WORK_DIR/askpass.sh"


cat > "$ASKPASS" <<'EOF'
#!/usr/bin/env sh

case "$1" in

    *Username*)
        printf '%s\n' "$GITEA_PUSH_USER"
        ;;

    *Password*)
        printf '%s\n' "$GITEA_PUSH_PASSWORD"
        ;;

esac
EOF


chmod 700 "$ASKPASS"


export GITEA_PUSH_USER="$GITEA_ADMIN_USER"

export GITEA_PUSH_PASSWORD="$GITEA_ADMIN_PASSWORD"

export GIT_ASKPASS="$ASKPASS"

export GIT_TERMINAL_PROMPT=0


# --------------------------------------------------
# Push entire historical repository
# --------------------------------------------------

git remote set-url \
    origin \
    "https://10.13.10.20/git/${GITEA_ADMIN_USER}/deployment-tools.git"


git \
    -c http.sslVerify=false \
    push \
    --mirror \
    origin


echo
echo "=================================================="
echo " S01 Gitea seed complete"
echo "=================================================="
echo

echo "Repository:"
echo "https://10.13.10.20/git/${GITEA_ADMIN_USER}/deployment-tools"