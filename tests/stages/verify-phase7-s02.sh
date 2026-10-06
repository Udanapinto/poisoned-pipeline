#!/usr/bin/env bash
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

source "$ROOT_DIR/private/s01/s01.env"
source "$ROOT_DIR/private/s02/s02.env"
source "$ROOT_DIR/private/s02/baseline.env"

BASE="https://10.13.10.20/jenkins"
AUTH="$S01_JENKINS_USER:$S01_JENKINS_PASSWORD"

PASS=0
FAIL=0

pass() {
    echo "[PASS] $1"
    PASS=$((PASS + 1))
}

fail() {
    echo "[FAIL] $1"
    FAIL=$((FAIL + 1))
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "======================================================"
echo " PHASE 7 - S02 PIPELINE BREACH VERIFICATION"
echo "======================================================"
echo

# --------------------------------------------------
# Container exists
# --------------------------------------------------

if docker inspect pp-jenkins >/dev/null 2>&1; then
    pass "Jenkins container exists"
else
    fail "Jenkins container exists"
fi

# --------------------------------------------------
# Jenkins host port must NOT be published
# --------------------------------------------------

if [[ -z "$(docker port pp-jenkins 2>/dev/null)" ]]; then
    pass "Jenkins backend port is not host-published"
else
    fail "Jenkins backend port is not host-published"
fi

# --------------------------------------------------
# Docker socket must NOT be mounted
# --------------------------------------------------

if docker inspect pp-jenkins \
    | grep -Fq '/var/run/docker.sock'
then
    fail "Jenkins has no Docker socket"
else
    pass "Jenkins has no Docker socket"
fi

# --------------------------------------------------
# Anonymous artifact retrieval must fail
# --------------------------------------------------

ANON_CODE="$(
curl -k -s \
-o /dev/null \
-w '%{http_code}' \
"$BASE/job/$EXPECTED_JOB_NAME/103/artifact/artifact-output/release-manifest.txt"
)"

if [[ "$ANON_CODE" != "200" ]]; then
    pass "Anonymous user cannot retrieve S02 manifest"
else
    fail "Anonymous user cannot retrieve S02 manifest"
fi

# --------------------------------------------------
# Reader can enumerate job
# --------------------------------------------------

READER_CODE="$(
curl -k -s \
-u "$AUTH" \
-o /dev/null \
-w '%{http_code}' \
"$BASE/job/$EXPECTED_JOB_NAME/api/json"
)"

if [[ "$READER_CODE" == "200" ]]; then
    pass "Recovered S01 account can read Jenkins job"
else
    fail "Recovered S01 account can read Jenkins job"
fi

# --------------------------------------------------
# Reader can retrieve compromised manifest
# --------------------------------------------------

curl -ksS \
-u "$AUTH" \
"$BASE/job/$EXPECTED_JOB_NAME/103/artifact/artifact-output/release-manifest.txt" \
-o "$TMP/release-manifest.txt"

if grep -Fq "$S02_FLAG" \
"$TMP/release-manifest.txt"
then
    pass "Build 103 artifact contains S02 token"
else
    fail "Build 103 artifact contains S02 token"
fi

# --------------------------------------------------
# Console must not contain flag
# --------------------------------------------------

curl -ksS \
-u "$AUTH" \
"$BASE/job/$EXPECTED_JOB_NAME/103/consoleText" \
-o "$TMP/console.txt"

if grep -Fq "$S02_FLAG" "$TMP/console.txt"; then
    fail "Build console does not expose S02 token"
else
    pass "Build console does not expose S02 token"
fi

# --------------------------------------------------
# S03 handoff is downloadable by reader
# --------------------------------------------------

EVIDENCE_CODE="$(
curl -k -s \
-u "$AUTH" \
-o "$TMP/evidence-s03.zip" \
-w '%{http_code}' \
"$BASE/job/$EXPECTED_JOB_NAME/103/artifact/artifact-output/evidence-s03.zip"
)"

if [[ "$EVIDENCE_CODE" == "200" ]]; then
    pass "Reader can download S03 evidence handoff"
else
    fail "Reader can download S03 evidence handoff"
fi

# --------------------------------------------------
# Verify evidence checksum against baseline
# --------------------------------------------------

ACTUAL_EVIDENCE_SHA="$(
sha256sum "$TMP/evidence-s03.zip" \
| awk '{print $1}'
)"

if [[ "$ACTUAL_EVIDENCE_SHA" == "$S03_EVIDENCE_SHA256" ]]; then
    pass "S03 evidence checksum matches baseline"
else
    fail "S03 evidence checksum matches baseline"
fi

# --------------------------------------------------
# Reader must not be able to configure job
# --------------------------------------------------

CONFIG_CODE="$(
curl -k -s \
-u "$AUTH" \
-o /dev/null \
-w '%{http_code}' \
"$BASE/job/$EXPECTED_JOB_NAME/config.xml"
)"

if [[ "$CONFIG_CODE" != "200" ]]; then
    pass "Reader cannot retrieve job configuration"
else
    fail "Reader cannot retrieve job configuration"
fi

# --------------------------------------------------
# Verify only build 103 contains S03 bundle
# --------------------------------------------------

for BUILD in 101 102 104; do

    CODE="$(
    curl -k -s \
    -u "$AUTH" \
    -o /dev/null \
    -w '%{http_code}' \
    "$BASE/job/$EXPECTED_JOB_NAME/$BUILD/artifact/artifact-output/evidence-s03.zip"
    )"

    if [[ "$CODE" != "200" ]]; then
        pass "Build $BUILD does not expose S03 bundle"
    else
        fail "Build $BUILD does not expose S03 bundle"
    fi
done

echo
echo "======================================================"
echo " RESULTS"
echo "======================================================"
echo
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo

if [[ "$FAIL" -eq 0 ]]; then
    echo "PHASE 7 S02: PASSED"
    exit 0
else
    echo "PHASE 7 S02: FAILED"
    exit 1
fi