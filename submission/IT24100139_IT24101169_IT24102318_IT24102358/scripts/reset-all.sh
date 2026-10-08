#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

echo "======================================================"
echo " Operation Poisoned Pipeline"
echo " Master Reset"
echo "======================================================"
echo

echo "[1/8] Resetting S01 (Gitea)..."
"${ROOT_DIR}/scripts/reset-s01.sh"
echo

echo "[2/8] Resetting S02 (Jenkins)..."
"${ROOT_DIR}/scripts/reset-s02.sh"
echo

echo "[3/8] Resetting S03 (Ghost Dependency)..."
"${ROOT_DIR}/scripts/reset-s03.sh"
echo

echo "[4/8] Resetting S04 (Poisoned Runtime)..."
"${ROOT_DIR}/scripts/reset-s04.sh"
echo

echo "[5/8] Resetting S05 (Broken Trust)..."
"${ROOT_DIR}/scripts/reset-s05.sh"
echo

echo "[6/8] Resetting S06 (Behind the Firewall)..."
"${ROOT_DIR}/scripts/reset-s06.sh"
echo

echo "[7/8] Resetting Kali participant..."
"${ROOT_DIR}/scripts/reset-phase13-kali.sh"
echo

echo "[8/8] Verifying all stages..."
"${ROOT_DIR}/tests/stages/verify-phase8-s03.sh"
"${ROOT_DIR}/tests/stages/verify-phase10-s04.sh"
"${ROOT_DIR}/tests/stages/verify-phase11-s05.sh"
"${ROOT_DIR}/tests/stages/verify-phase12-s06.sh"
"${ROOT_DIR}/tests/stages/verify-phase13-kali.sh"
"${ROOT_DIR}/tests/stages/verify-phase14-ctfd.sh"

echo
echo "======================================================"
echo " ALL RESETS COMPLETE"
echo "======================================================"
