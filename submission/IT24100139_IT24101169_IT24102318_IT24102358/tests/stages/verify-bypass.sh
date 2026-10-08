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
echo " Bypass Testing"
echo "======================================================"
echo

# --- S01: Flag not in current tree ---
if docker exec pp-kali sh -lc '
    rm -rf /tmp/s01-bypass
    git -c http.sslVerify=false clone https://10.13.10.20/git/nexora/deployment-tools.git /tmp/s01-bypass 2>/dev/null
    cd /tmp/s01-bypass
    ! grep -R "IE3132{PP_S01_" --exclude-dir=.git . 2>/dev/null
' >/dev/null 2>&1; then
    pass "S01: flag not in current tree"
else
    fail "S01: flag not in current tree"
fi

# --- S01: Jenkins credential not in current tree ---
if docker exec pp-kali sh -lc '
    cd /tmp/s01-bypass
    ! grep -R "JENKINS_PASSWORD" --exclude-dir=.git . 2>/dev/null
' >/dev/null 2>&1; then
    pass "S01: Jenkins credential not in current tree"
else
    fail "S01: Jenkins credential not in current tree"
fi

# --- S02: Anonymous Jenkins access fails ---
ANON_CODE="$(docker exec pp-kali curl -kfsS -o /dev/null -w '%{http_code}' \
    'https://10.13.10.20/jenkins/job/nexora-release/103/artifact/artifact-output/evidence-s03.zip' \
    2>/dev/null || true)"

if [[ "${ANON_CODE}" != "200" ]]; then
    pass "S02: anonymous artifact access denied (${ANON_CODE})"
else
    fail "S02: anonymous artifact access denied (got 200)"
fi

# --- S02: Reader cannot build ---
source private/s01/s01.env
BUILD_CODE="$(docker exec pp-kali sh -lc "
    curl -kfsS -u '${S01_JENKINS_USER}:${S01_JENKINS_PASSWORD}' \
        -X POST -o /dev/null -w '%{http_code}' \
        'https://10.13.10.20/jenkins/job/${S01_JOB_NAME}/build' 2>/dev/null
" || true)"

if [[ "${BUILD_CODE}" == "403" ]]; then
    pass "S02: reader cannot trigger builds (403)"
else
    fail "S02: reader cannot trigger builds (got ${BUILD_CODE})"
fi

# --- S03: No literal flag in evidence ---
if unzip -p challenges/s03-ghost-dependency/dist/evidence-s03.zip 2>/dev/null | grep -q 'IE3132{'; then
    fail "S03: no literal flag in evidence bundle"
else
    pass "S03: no literal flag in evidence bundle"
fi

# --- S04: Cannot read /etc/shadow ---
SHADOW_OUT="$(docker exec pp-kali sh -lc "
    curl -kfsS -X POST \
        -H 'Content-Type: application/json' \
        -d '{\"component\":\"nexora-utils; cat /etc/shadow 2>&1 || true\"}' \
        http://10.13.10.30:5000/api/diagnostics/run 2>/dev/null
" || true)"

if grep -q 'Permission denied' <<<"${SHADOW_OUT}"; then
    pass "S04: pipeline-app cannot read /etc/shadow"
else
    fail "S04: pipeline-app cannot read /etc/shadow"
fi

# --- S05: S05/S06 secrets not readable pre-escalation ---
if docker exec --user 10001:10001 pp-application sh -lc '
    test -r /root/s05_flag.txt
' >/dev/null 2>&1; then
    fail "S05: pipeline-app cannot read S05 flag pre-escalation"
else
    pass "S05: pipeline-app cannot read S05 flag pre-escalation"
fi

if docker exec --user 10001:10001 pp-application sh -lc '
    test -r /root/s06_pivot.txt
' >/dev/null 2>&1; then
    fail "S05: pipeline-app cannot read S06 pivot pre-escalation"
else
    pass "S05: pipeline-app cannot read S06 pivot pre-escalation"
fi


# --- S05: Direct sudo to shell denied (must run as pipeline-app) ---
if docker exec --user 10001:10001 pp-application sh -lc '
    sudo -n /bin/bash -c "id" >/dev/null 2>&1
' ; then
    fail "S05: direct sudo to /bin/bash denied"
else
    pass "S05: direct sudo to /bin/bash denied"
fi

if docker exec --user 10001:10001 pp-application sh -lc '
    sudo -n /bin/sh -c "id" >/dev/null 2>&1
' ; then
    fail "S05: direct sudo to /bin/sh denied"
else
    pass "S05: direct sudo to /bin/sh denied"
fi

if docker exec --user 10001:10001 pp-application sh -lc '
    sudo -n /usr/bin/python3 -c "import os; print(os.getuid())" >/dev/null 2>&1
' ; then
    fail "S05: direct sudo to python denied"
else
    pass "S05: direct sudo to python denied"
fi

# --- S06: Direct PostgreSQL access from Kali denied ---
if docker exec --user 10001:10001 pp-kali nc -z -w 3 10.13.20.10 5432 >/dev/null 2>&1; then
    fail "S06: Kali cannot reach PostgreSQL directly"
else
    pass "S06: Kali cannot reach PostgreSQL directly"
fi

# --- S06: Database writes denied ---
source private/s06/s06.env
if docker compose exec -T postgres \
    env PGPASSWORD="${DB_READER_PASSWORD}" \
    psql -h 127.0.0.1 -U "${DB_READER_USER}" -d "${POSTGRES_DB}" \
    -c "INSERT INTO ctf_final (record_key, record_value) VALUES ('x','y');" \
    >/dev/null 2>&1; then
    fail "S06: ctf_reader cannot INSERT"
else
    pass "S06: ctf_reader cannot INSERT"
fi

echo
echo "======================================================"
echo " RESULTS"
echo "======================================================"
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"
echo

if [[ "${FAIL}" -eq 0 ]]; then
    echo "BYPASS TESTING: PASSED"
    exit 0
else
    echo "BYPASS TESTING: FAILED"
    exit 1
fi
