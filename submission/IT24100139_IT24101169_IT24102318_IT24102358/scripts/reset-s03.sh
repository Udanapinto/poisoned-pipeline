#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"

echo "=================================================="
echo " Operation Poisoned Pipeline"
echo " S03 Reset"
echo "=================================================="
echo

echo "[+] Regenerating S03 evidence..."
"$ROOT_DIR/scripts/generate-s03-evidence.sh"

echo
echo "[+] Re-seeding Jenkins build history..."
"$ROOT_DIR/scripts/reset-s02.sh"

echo
echo "[+] Verifying S03..."
"$ROOT_DIR/tests/stages/verify-phase8-s03.sh"

echo
echo "=================================================="
echo " S03 RESET COMPLETE"
echo "=================================================="