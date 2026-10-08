#!/usr/bin/env bash
# S01 - The Git Leak
# Reference solver for the intended solution path.
# Authorized use only inside the isolated Operation Poisoned Pipeline lab.
#
# Intended path:
# 1. Clone the simulated repository.
# 2. Inspect commit history.
# 3. Recover the S01 token, Jenkins credential, and job clue.

set -euo pipefail

GITEA_URL="${GITEA_URL:-https://10.13.10.20/git/nexora/deployment-tools.git}"
WORK_DIR="${1:-/tmp/s01-solve}"

echo "======================================================"
echo " S01 - The Git Leak Solver"
echo "======================================================"
echo

rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"

echo "[1] Cloning repository..."
git -c http.sslVerify=false clone "${GITEA_URL}" "${WORK_DIR}/repo" 2>/dev/null
cd "${WORK_DIR}/repo"

echo "[2] Current branch files:"
ls -la

echo
echo "[3] Searching current tree for secrets..."
if grep -R "IE3132{PP_S01_" --exclude-dir=.git . 2>/dev/null; then
    echo "[!] Unexpected: flag found in current tree."
    exit 1
else
    echo "    PASS: no S01 flag in current tree."
fi

if grep -R "JENKINS_PASSWORD" --exclude-dir=.git . 2>/dev/null; then
    echo "[!] Unexpected: Jenkins password found in current tree."
    exit 1
else
    echo "    PASS: no Jenkins password in current tree."
fi

echo
echo "[4] Commit history:"
git log --oneline --all

echo
echo "[5] Searching full history for the accidental disclosure..."
git log -p --all | grep -E "(IE3132\{PP_S01_|JENKINS_USER=|JENKINS_PASSWORD=|JENKINS_JOB=)" || true

echo
echo "[6] Relevant commit that introduced the disclosure:"
LEAK_COMMIT="$(git log --all --oneline -S 'JENKINS_PASSWORD' --pickaxe-regex --format='%H' | head -n 1)"
echo "    ${LEAK_COMMIT}"

if [[ -n "${LEAK_COMMIT}" ]]; then
    echo
    echo "[7] Commit diff:"
    git show "${LEAK_COMMIT}"
fi

echo
echo "======================================================"
echo " S01 solve complete."
echo " Submit the S01 token to CTFd."
echo " Record the Jenkins credential and job clue for S02."
echo "======================================================"
