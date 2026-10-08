#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

S01_FILE="$ROOT_DIR/private/s01/s01.env"
S02_FILE="$ROOT_DIR/private/s02/s02.env"

JOB_XML="$ROOT_DIR/jenkins/jobs/nexora-release.xml"

BASE_URL="https://10.13.10.20/jenkins"

# ==========================================================
# Validate required files
# ==========================================================

if [[ ! -f "$S01_FILE" ]]; then
    echo "[ERROR] Missing $S01_FILE"
    exit 1
fi

if [[ ! -f "$S02_FILE" ]]; then
    echo "[ERROR] Missing $S02_FILE"
    exit 1
fi

if [[ ! -f "$JOB_XML" ]]; then
    echo "[ERROR] Missing $JOB_XML"
    exit 1
fi

# shellcheck disable=SC1090
source "$S01_FILE"

# shellcheck disable=SC1090
source "$S02_FILE"

JOB="${S01_JOB_NAME}"
AUTH="${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASSWORD}"

# ==========================================================
# Temporary files
# ==========================================================

COOKIE_JAR="$(mktemp)"
SCRIPT_RESPONSE="$(mktemp)"
TMP_MANIFEST=""
TMP_EVIDENCE=""

cleanup() {

    rm -f "$COOKIE_JAR"
    rm -f "$SCRIPT_RESPONSE"

    if [[ -n "$TMP_MANIFEST" ]]; then
        rm -f "$TMP_MANIFEST"
    fi

    if [[ -n "$TMP_EVIDENCE" ]]; then
        rm -f "$TMP_EVIDENCE"
    fi
}

trap cleanup EXIT


echo "=================================================="
echo " Operation Poisoned Pipeline"
echo " S02 Jenkins Seeder"
echo "=================================================="
echo


# ==========================================================
# Wait for Jenkins
# ==========================================================

echo "[+] Waiting for Jenkins..."

READY=0

for attempt in $(seq 1 60); do

    CODE="$(
        curl -k -s \
            -o /dev/null \
            -w '%{http_code}' \
            "$BASE_URL/login" \
            || true
    )"

    if [[ "$CODE" == "200" ]]; then

        READY=1
        break

    fi

    sleep 2
done

if [[ "$READY" != "1" ]]; then

    echo "[ERROR] Jenkins did not become available."
    exit 1

fi

echo "[+] Jenkins is available."


# ==========================================================
# Helper: obtain a CSRF crumb using the SAME Jenkins session
#
# IMPORTANT:
# Jenkins crumbs are associated with the session.
# Therefore the cookie jar must be reused for every POST.
# ==========================================================

refresh_crumb() {

    CRUMB_JSON="$(
        curl -k -sS \
            -u "$AUTH" \
            -c "$COOKIE_JAR" \
            -b "$COOKIE_JAR" \
            "$BASE_URL/crumbIssuer/api/json"
    )"

    CRUMB_FIELD="$(
        jq -r '.crumbRequestField // empty' \
        <<< "$CRUMB_JSON"
    )"

    CRUMB="$(
        jq -r '.crumb // empty' \
        <<< "$CRUMB_JSON"
    )"

    if [[ -z "$CRUMB_FIELD" || -z "$CRUMB" ]]; then

        echo "[ERROR] Could not obtain Jenkins CSRF crumb."
        echo "[ERROR] Jenkins returned:"
        echo "$CRUMB_JSON"

        exit 1

    fi
}


# ==========================================================
# Authenticate administrator
# ==========================================================

refresh_crumb

echo "[+] Administrator authentication successful."


# ==========================================================
# Remove existing seeded job if present
# ==========================================================

JOB_CODE="$(
    curl -k -s \
        -u "$AUTH" \
        -b "$COOKIE_JAR" \
        -o /dev/null \
        -w '%{http_code}' \
        "$BASE_URL/job/$JOB/api/json"
)"

if [[ "$JOB_CODE" == "200" ]]; then

    echo "[+] Removing previous seed job."

    refresh_crumb

    DELETE_HTTP="$(
        curl -k -sS \
            -u "$AUTH" \
            -b "$COOKIE_JAR" \
            -c "$COOKIE_JAR" \
            -H "$CRUMB_FIELD: $CRUMB" \
            -X POST \
            -o /dev/null \
            -w '%{http_code}' \
            "$BASE_URL/job/$JOB/doDelete"
    )"

    if [[ "$DELETE_HTTP" != "200" \
       && "$DELETE_HTTP" != "302" ]]; then

        echo "[ERROR] Could not remove previous Jenkins job."
        echo "[ERROR] HTTP status: $DELETE_HTTP"
        exit 1

    fi

    sleep 2
fi


# ==========================================================
# Create Jenkins job
# ==========================================================

echo "[+] Creating Jenkins job: $JOB"

refresh_crumb

CREATE_HTTP="$(
    curl -k -sS \
        -u "$AUTH" \
        -b "$COOKIE_JAR" \
        -c "$COOKIE_JAR" \
        -H "$CRUMB_FIELD: $CRUMB" \
        -H "Content-Type: application/xml" \
        --data-binary "@$JOB_XML" \
        -X POST \
        -o /dev/null \
        -w '%{http_code}' \
        "$BASE_URL/createItem?name=$JOB"
)"

if [[ "$CREATE_HTTP" != "200" \
   && "$CREATE_HTTP" != "201" \
   && "$CREATE_HTTP" != "302" ]]; then

    echo "[ERROR] Jenkins job creation failed."
    echo "[ERROR] HTTP status: $CREATE_HTTP"
    exit 1

fi

echo "[+] Jenkins job created."


# ==========================================================
# Set historical next build number to 101
#
# The private administrator performs this during seeding.
#
# The participant account does NOT have:
#
# - Overall/Administer
# - Script Console
# - Job/Build
# - Job/Configure
# ==========================================================

echo "[+] Setting historical build baseline to #101."

refresh_crumb

GROOVY="
def job = jenkins.model.Jenkins.get().getItemByFullName('${JOB}')

if (job == null) {
    throw new RuntimeException('Jenkins job not found')
}

job.updateNextBuildNumber(101)

println(job.getNextBuildNumber())
"

SCRIPT_HTTP="$(
    curl -k -sS \
        -u "$AUTH" \
        -b "$COOKIE_JAR" \
        -c "$COOKIE_JAR" \
        -H "$CRUMB_FIELD: $CRUMB" \
        -X POST \
        --data-urlencode "script=$GROOVY" \
        -o "$SCRIPT_RESPONSE" \
        -w '%{http_code}' \
        "$BASE_URL/scriptText"
)"

if [[ "$SCRIPT_HTTP" != "200" ]]; then

    echo "[ERROR] Jenkins Script Console request failed."
    echo "[ERROR] HTTP status: $SCRIPT_HTTP"
    echo
    cat "$SCRIPT_RESPONSE"
    exit 1

fi

echo "[+] Jenkins accepted historical build-number update."


# ==========================================================
# Verify nextBuildNumber == 101
# ==========================================================

NEXT_BUILD="$(
    curl -k -sS \
        -u "$AUTH" \
        -b "$COOKIE_JAR" \
        "$BASE_URL/job/$JOB/api/json" \
    | jq -r '.nextBuildNumber'
)"

echo "[+] Jenkins reports next build number: $NEXT_BUILD"

if [[ "$NEXT_BUILD" != "101" ]]; then

    echo "[ERROR] Historical build numbering was not applied."
    echo "[ERROR] Expected: 101"
    echo "[ERROR] Actual:   $NEXT_BUILD"

    exit 1

fi

echo "[+] Historical build baseline verified."


# ==========================================================
# Seed builds:
#
# 101 = normal
# 102 = normal
# 103 = compromised
# 104 = normal
# ==========================================================

for BUILD_NUMBER in 101 102 103 104; do

    echo
    echo "[+] Starting synthetic build #$BUILD_NUMBER"

    refresh_crumb

    TRIGGER_HTTP="$(
        curl -k -sS \
            -u "$AUTH" \
            -b "$COOKIE_JAR" \
            -c "$COOKIE_JAR" \
            -H "$CRUMB_FIELD: $CRUMB" \
            -X POST \
            -o /dev/null \
            -w '%{http_code}' \
            "$BASE_URL/job/$JOB/build?delay=0sec"
    )"

    echo "[+] Build trigger returned HTTP $TRIGGER_HTTP"

    if [[ "$TRIGGER_HTTP" != "200" \
       && "$TRIGGER_HTTP" != "201" \
       && "$TRIGGER_HTTP" != "302" ]]; then

        echo "[ERROR] Jenkins rejected build #$BUILD_NUMBER trigger."
        exit 1

    fi


    # ------------------------------------------------------
    # Wait for build to exist and complete
    # ------------------------------------------------------

    RESULT=""
    BUILDING=""

    for attempt in $(seq 1 90); do

        STATUS_FILE="$(mktemp)"

        BUILD_HTTP="$(
            curl -k -s \
                -u "$AUTH" \
                -b "$COOKIE_JAR" \
                -o "$STATUS_FILE" \
                -w '%{http_code}' \
                "$BASE_URL/job/$JOB/$BUILD_NUMBER/api/json"
        )"

        if [[ "$BUILD_HTTP" != "200" ]]; then

            rm -f "$STATUS_FILE"
            sleep 2
            continue

        fi

        ACTUAL_NUMBER="$(
            jq -r '.number // empty' \
            "$STATUS_FILE"
        )"

        BUILDING="$(
            jq -r '.building // empty' \
            "$STATUS_FILE"
        )"

        RESULT="$(
            jq -r '.result // empty' \
            "$STATUS_FILE"
        )"

        rm -f "$STATUS_FILE"

        if [[ "$ACTUAL_NUMBER" == "$BUILD_NUMBER" \
           && "$BUILDING" == "false" \
           && -n "$RESULT" ]]; then

            break

        fi

        sleep 2

    done


    # ------------------------------------------------------
    # Verify successful build
    # ------------------------------------------------------

    if [[ "$RESULT" != "SUCCESS" ]]; then

        echo
        echo "[ERROR] Build #$BUILD_NUMBER did not complete successfully."
        echo "[ERROR] Result: ${RESULT:-unknown}"
        echo

        echo "[+] Current Jenkins build state:"

        curl -k -sS \
            -u "$AUTH" \
            -b "$COOKIE_JAR" \
            "$BASE_URL/job/$JOB/api/json" \
        | jq '{
            name,
            nextBuildNumber,
            builds: [
                .builds[] |
                {
                    number,
                    result
                }
            ]
        }'

        echo
        echo "[+] Build #$BUILD_NUMBER console output:"
        echo

        curl -k -sS \
            -u "$AUTH" \
            -b "$COOKIE_JAR" \
            "$BASE_URL/job/$JOB/$BUILD_NUMBER/consoleText" \
        | tail -100 || true

        exit 1

    fi

    echo "[+] Build #$BUILD_NUMBER completed successfully."

done


# ==========================================================
# Disable historical job
#
# Participants should inspect history, not create builds.
# ==========================================================

echo
echo "[+] Disabling historical job."

refresh_crumb

DISABLE_HTTP="$(
    curl -k -sS \
        -u "$AUTH" \
        -b "$COOKIE_JAR" \
        -c "$COOKIE_JAR" \
        -H "$CRUMB_FIELD: $CRUMB" \
        -X POST \
        -o /dev/null \
        -w '%{http_code}' \
        "$BASE_URL/job/$JOB/disable"
)"

if [[ "$DISABLE_HTTP" != "200" \
   && "$DISABLE_HTTP" != "302" ]]; then

    echo "[ERROR] Could not disable Jenkins job."
    echo "[ERROR] HTTP status: $DISABLE_HTTP"

    exit 1

fi

echo "[+] Historical Jenkins job disabled."


# ==========================================================
# Download intended build #103 artifacts
#
# IMPORTANT:
# Use the S01-recovered pipeline-reader account here.
#
# This simultaneously verifies the actual intended S02
# permission path:
#
# pipeline-reader
#        |
#        +--> Job/Read
#        |
#        +--> Run/Artifacts
#
# Administrator privilege is NOT required to retrieve
# the challenge evidence.
# ==========================================================

TMP_MANIFEST="$(mktemp)"
TMP_EVIDENCE="$(mktemp)"

READER_AUTH="${S01_JENKINS_USER}:${S01_JENKINS_PASSWORD}"

echo
echo "[+] Verifying S02 artifact access as pipeline-reader."


# ----------------------------------------------------------
# Build #103 release manifest
# ----------------------------------------------------------

MANIFEST_HTTP="$(
    curl -k -sS \
        -u "$READER_AUTH" \
        -o "$TMP_MANIFEST" \
        -w '%{http_code}' \
        "$BASE_URL/job/$JOB/103/artifact/artifact-output/release-manifest.txt"
)"

if [[ "$MANIFEST_HTTP" != "200" ]]; then

    echo "[ERROR] pipeline-reader could not retrieve build #103 manifest."
    echo "[ERROR] HTTP status: $MANIFEST_HTTP"
    echo
    echo "[ERROR] Check Jenkins permissions:"
    echo "        Overall/Read"
    echo "        Job/Read"
    echo "        Run/Artifacts"

    exit 1

fi

echo "[+] pipeline-reader retrieved build #103 manifest."


# ----------------------------------------------------------
# Build #103 S03 evidence bundle
# ----------------------------------------------------------

EVIDENCE_HTTP="$(
    curl -k -sS \
        -u "$READER_AUTH" \
        -o "$TMP_EVIDENCE" \
        -w '%{http_code}' \
        "$BASE_URL/job/$JOB/103/artifact/artifact-output/evidence-s03.zip"
)"

if [[ "$EVIDENCE_HTTP" != "200" ]]; then

    echo "[ERROR] pipeline-reader could not retrieve S03 evidence bundle."
    echo "[ERROR] HTTP status: $EVIDENCE_HTTP"

    exit 1

fi

echo "[+] pipeline-reader retrieved S03 evidence bundle."


# ==========================================================
# Verify intended artifact content
# ==========================================================

if grep -Fq "$S02_FLAG" "$TMP_MANIFEST"; then

    echo "[+] S02 token confirmed in intended build artifact."

else

    echo "[ERROR] S02 token missing from intended build artifact."
    exit 1

fi


if unzip -t "$TMP_EVIDENCE" >/dev/null 2>&1; then

    echo "[+] S03 evidence ZIP integrity verified."

else

    echo "[ERROR] evidence-s03.zip is invalid."
    exit 1

fi


# ==========================================================
# Verify intended artifact content
# ==========================================================

if grep -Fq "$S02_FLAG" "$TMP_MANIFEST"; then

    echo "[+] S02 token confirmed in intended build artifact."

else

    echo "[ERROR] S02 token missing from intended build artifact."
    exit 1

fi


if unzip -t "$TMP_EVIDENCE" >/dev/null 2>&1; then

    echo "[+] S03 evidence ZIP integrity verified."

else

    echo "[ERROR] evidence-s03.zip is invalid."
    exit 1

fi


# ==========================================================
# Create private baseline
# ==========================================================

MANIFEST_SHA="$(
    sha256sum "$TMP_MANIFEST" \
    | awk '{print $1}'
)"

EVIDENCE_SHA="$(
    sha256sum "$TMP_EVIDENCE" \
    | awk '{print $1}'
)"

CASC_SHA="$(
    sha256sum "$ROOT_DIR/jenkins/casc/jenkins.yaml" \
    | awk '{print $1}'
)"

JOB_SHA="$(
    sha256sum "$ROOT_DIR/jenkins/jobs/nexora-release.xml" \
    | awk '{print $1}'
)"

cat > "$ROOT_DIR/private/s02/baseline.env" <<EOF
EXPECTED_JOB_NAME=$JOB
EXPECTED_COMPROMISED_BUILD=103

JENKINS_CASC_SHA256=$CASC_SHA
JENKINS_JOB_SEED_SHA256=$JOB_SHA

S02_MANIFEST_SHA256=$MANIFEST_SHA
S03_EVIDENCE_SHA256=$EVIDENCE_SHA
EOF

chmod 600 "$ROOT_DIR/private/s02/baseline.env"


echo
echo "=================================================="
echo " S02 JENKINS SEED COMPLETE"
echo "=================================================="