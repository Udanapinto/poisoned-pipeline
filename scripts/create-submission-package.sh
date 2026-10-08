#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

SUBMISSION_DIR="${ROOT_DIR}/submission"
PACKAGE_NAME="IT24100139_IT24101169_IT24102318_IT24102358"

echo "=========================================="
echo " Operation Poisoned Pipeline"
echo " Submission Package Creator"
echo "=========================================="
echo

rm -rf "${SUBMISSION_DIR}"
mkdir -p "${SUBMISSION_DIR}/${PACKAGE_NAME}"

TARGET="${SUBMISSION_DIR}/${PACKAGE_NAME}"

echo "[+] Copying public-safe project files..."

# Core project files
cp compose.yml "${TARGET}/"
cp .env.example "${TARGET}/"
cp .gitignore "${TARGET}/"
cp README.md "${TARGET}/"

# Application
cp -r application "${TARGET}/"

# Kali
cp -r kali "${TARGET}/"

# Challenges (source and solvers, not private data)
cp -r challenges "${TARGET}/"

# Scripts (public-safe only)
mkdir -p "${TARGET}/scripts"
for script in \
    generate-s01-secrets.sh \
    generate-s02-secrets.sh \
    generate-s03-secrets.sh \
    generate-s04-secrets.sh \
    generate-s05-secrets.sh \
    generate-s06-secrets.sh \
    build-application.sh \
    seed-gitea-s01.sh \
    seed-jenkins-s02.sh \
    seed-postgres-s06.sh \
    generate-s03-evidence.sh \
    reset-s01.sh \
    reset-s02.sh \
    reset-s03.sh \
    reset-s04.sh \
    reset-s05.sh \
    reset-s06.sh \
    reset-phase13-kali.sh \
    reset-all.sh \
    generate-build-manifest.sh \
    ctfd-export-challenges.sh \
    ctfd-apply-challenges.py
do
    if [[ -f "scripts/${script}" ]]; then
        cp "scripts/${script}" "${TARGET}/scripts/"
    fi
done

# Tests
cp -r tests "${TARGET}/"

# Nginx config
cp -r nginx "${TARGET}/"

# Jenkins config
cp -r jenkins "${TARGET}/"

# PostgreSQL init
cp -r postgres "${TARGET}/"

# Gitea seeds (public key only)
mkdir -p "${TARGET}/gitea/seeds"
if [[ -f "gitea/seeds/s01-signing-public.pem" ]]; then
    cp "gitea/seeds/s01-signing-public.pem" "${TARGET}/gitea/seeds/"
fi

# S03 public keys
mkdir -p "${TARGET}/challenges/s03-ghost-dependency/keys"
if [[ -f "challenges/s03-ghost-dependency/keys/s03-signing-public.pem" ]]; then
    cp "challenges/s03-ghost-dependency/keys/s03-signing-public.pem" "${TARGET}/challenges/s03-ghost-dependency/keys/"
fi

# Evidence
cp -r evidence "${TARGET}/"

# Documentation
mkdir -p "${TARGET}/docs"
for doc in \
    "IT24100139_IE3132_CTF_Design.pdf" \
    "1 Project implementation plan.pdf" \
    "Phase 4 - DONE.pdf" \
    "Phase 5 - DONE.pdf" \
    "Phase 6 - DONE.pdf" \
    "Phase 7 - DONE.pdf" \
    "Phase 8 - DONE.pdf" \
    "Phase 9 - DONE.pdf" \
    "Phase 10 - DONE.pdf" \
    "Phase 11 - DONE.pdf" \
    "Phase 12 - DONE.pdf"
do
    if [[ -f "${ROOT_DIR}/${doc}" ]]; then
        cp "${ROOT_DIR}/${doc}" "${TARGET}/docs/"
    fi
done

# Create README for the submission package
cat > "${TARGET}/SUBMISSION-README.md" <<'EOF'
# Operation Poisoned Pipeline - Submission Package

This package contains the complete CTF Play Box implementation for the
IE3132 Penetration Testing module.

## Contents

- `compose.yml`: Docker Compose orchestration
- `application/`: Application Challenge container source
- `kali/`: Kali participant container source
- `challenges/`: Challenge source, solvers, and evidence
- `scripts/`: Build, seed, reset, and utility scripts
- `tests/`: Verification and testing scripts
- `nginx/`: Nginx reverse proxy configuration
- `jenkins/`: Jenkins Configuration as Code
- `postgres/`: PostgreSQL database initialization
- `evidence/`: Test results and verification outputs
- `docs/`: Design documents and phase implementation guides

## Setup

See the main `README.md` for full setup instructions.

## Important Notes

- The `private/` directory is not included in this package because it
  contains real flag values, passwords, and signing keys.
- To deploy, you must generate fresh secrets using the scripts in
  `scripts/generate-*-secrets.sh`.
- The CTFd challenge configuration is documented in
  `scripts/ctfd-export-challenges.sh`.

## Contact

- IT24100139 - Pinthu D.I.U.
- IT24101169 - Weligampitiya S.A.S.D.
- IT24102318 - Wickrama Edirisooriya A.A.G
- IT24102358 - Silva D.P.L.T.D.
EOF

echo "[+] Creating archive..."

cd "${SUBMISSION_DIR}"
tar -czf "${PACKAGE_NAME}.tar.gz" "${PACKAGE_NAME}"
zip -qr "${PACKAGE_NAME}.zip" "${PACKAGE_NAME}"

echo
echo "=========================================="
echo " SUBMISSION PACKAGE COMPLETE"
echo "=========================================="
echo
echo "Package directory: ${SUBMISSION_DIR}/${PACKAGE_NAME}"
echo "Tarball: ${SUBMISSION_DIR}/${PACKAGE_NAME}.tar.gz"
echo "Zip:     ${SUBMISSION_DIR}/${PACKAGE_NAME}.zip"
echo
echo "Review the package contents before submission:"
echo "  ls -la ${SUBMISSION_DIR}/${PACKAGE_NAME}"
echo
