#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

SECRET_FILE="$ROOT_DIR/private/s01/s01.env"

PRIVATE_DIR="$ROOT_DIR/private/s01"

BUNDLE="$PRIVATE_DIR/deployment-tools.bundle"

SIGNATURE="$PRIVATE_DIR/deployment-tools.bundle.sig"

BASELINE="$PRIVATE_DIR/baseline.env"

PRIVATE_KEY="$PRIVATE_DIR/s01-signing-private.pem"


# --------------------------------------------------
# Check required private files
# --------------------------------------------------

if [[ ! -f "$SECRET_FILE" ]]; then

    echo "[ERROR] Missing:"
    echo "        $SECRET_FILE"
    echo
    echo "Run:"
    echo "  ./scripts/generate-s01-secrets.sh"

    exit 1

fi


if [[ ! -f "$PRIVATE_KEY" ]]; then

    echo "[ERROR] Missing signing private key."
    exit 1

fi


# shellcheck disable=SC1090
source "$SECRET_FILE"


# --------------------------------------------------
# Temporary repository
# --------------------------------------------------

WORK_DIR="$(mktemp -d)"

cleanup() {

    rm -rf "$WORK_DIR"

}

trap cleanup EXIT


REPO="$WORK_DIR/deployment-tools"

mkdir -p "$REPO"

cd "$REPO"


git init -b main >/dev/null


git config user.name "Nexora DevOps"

git config user.email "devops@nexora.lab"


# ==================================================
# COMMIT 1
# Clean initial project
# ==================================================

cat > README.md <<'EOF'
# Nexora Deployment Tools

Internal deployment helper scripts used by the Nexora
software delivery team.

This repository contains deployment automation and
release-validation utilities.
EOF


mkdir -p scripts


cat > scripts/deploy.sh <<'EOF'
#!/usr/bin/env bash

set -e

echo "Starting Nexora deployment..."

echo "Validating release metadata..."

echo "Deployment workflow complete."
EOF


chmod +x scripts/deploy.sh


git add README.md scripts/deploy.sh

git commit \
    -m "Initial deployment tooling" \
    >/dev/null


# ==================================================
# COMMIT 2
# Normal deployment configuration
# ==================================================

mkdir -p config


cat > config/deployment.conf <<'EOF'
environment=staging
artifact_dir=/opt/nexora/releases
release_channel=stable
validation=true
EOF


git add config/deployment.conf

git commit \
    -m "Add deployment configuration" \
    >/dev/null


# ==================================================
# COMMIT 3
# INTENDED ACCIDENTAL SECRET DISCLOSURE
#
# This is the S01 historical object.
# ==================================================

cat > config/ci-integration.env <<EOF
# Legacy Jenkins integration

JENKINS_USER=${S01_JENKINS_USER}
JENKINS_PASSWORD=${S01_JENKINS_PASSWORD}
JENKINS_JOB=${S01_JOB_NAME}

S01_FLAG=${S01_FLAG}
EOF


git add config/ci-integration.env

git commit \
    -m "Add temporary CI integration configuration" \
    >/dev/null


LEAK_COMMIT="$(git rev-parse HEAD)"


# ==================================================
# COMMIT 4
# Developer realizes mistake and removes file
# ==================================================

git rm config/ci-integration.env >/dev/null


git commit \
    -m "Remove obsolete CI integration configuration" \
    >/dev/null


# ==================================================
# COMMIT 5
# Innocent later change
# ==================================================

cat >> README.md <<'EOF'

## Release Process

Deployment changes must be reviewed before production
promotion.
EOF


git add README.md

git commit \
    -m "Document release review process" \
    >/dev/null


# --------------------------------------------------
# Baseline data
# --------------------------------------------------

EXPECTED_HEAD="$(git rev-parse HEAD)"

COMMIT_COUNT="$(git rev-list --count HEAD)"


# --------------------------------------------------
# Verify current tree DOES NOT expose challenge data
# --------------------------------------------------

if git grep -n -E \
    'IE3132\{PP_S01_|JENKINS_PASSWORD|pipeline-reader' \
    HEAD -- . >/dev/null 2>&1
then

    echo "[ERROR] Current branch exposes S01 secrets!"
    exit 1

fi


# --------------------------------------------------
# Create clean Git bundle
# --------------------------------------------------

rm -f "$BUNDLE"

git bundle create "$BUNDLE" --all


BUNDLE_SHA256="$(sha256sum "$BUNDLE" | awk '{print $1}')"


# --------------------------------------------------
# Digitally sign bundle
# --------------------------------------------------

openssl dgst \
    -sha256 \
    -sign "$PRIVATE_KEY" \
    -out "$SIGNATURE" \
    "$BUNDLE"


# --------------------------------------------------
# Save private baseline
# --------------------------------------------------

cat > "$BASELINE" <<EOF
EXPECTED_HEAD=$EXPECTED_HEAD
EXPECTED_COMMIT_COUNT=$COMMIT_COUNT
LEAK_COMMIT=$LEAK_COMMIT
BUNDLE_SHA256=$BUNDLE_SHA256
EOF


chmod 600 "$BASELINE"


echo
echo "=================================================="
echo " S01 bundle successfully generated"
echo "=================================================="
echo

echo "Commit count:"
echo "  $COMMIT_COUNT"

echo

echo "Current HEAD:"
echo "  $EXPECTED_HEAD"

echo

echo "Bundle SHA-256:"
echo "  $BUNDLE_SHA256"

echo

echo "[PASS] Current branch contains no S01 flag."
echo "[PASS] Current branch contains no Jenkins password."
echo "[PASS] Historical disclosure exists."
echo
echo "Private bundle:"
echo "  private/s01/deployment-tools.bundle"
echo
echo "Private baseline:"
echo "  private/s01/baseline.env"