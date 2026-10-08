#!/usr/bin/env bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

BASELINE="$ROOT_DIR/private/s01/baseline.env"

PASS=0
FAIL=0

GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
RESET="\033[0m"


pass() {

    echo -e "${GREEN}[PASS]${RESET} $1"
    PASS=$((PASS + 1))

}


fail() {

    echo -e "${RED}[FAIL]${RESET} $1"
    FAIL=$((FAIL + 1))

}


info() {

    echo -e "${YELLOW}[INFO]${RESET} $1"

}


echo
echo "======================================================"
echo " Operation Poisoned Pipeline"
echo " Phase 6 - S01 The Git Leak Verification"
echo "======================================================"
echo


# --------------------------------------------------
# Gitea container
# --------------------------------------------------

info "Checking Gitea container..."

RUNNING="$(docker inspect \
    -f '{{.State.Running}}' \
    pp-gitea \
    2>/dev/null || true)"


if [[ "$RUNNING" == "true" ]]; then

    pass "Gitea container is running"

else

    fail "Gitea container is running"

fi


# --------------------------------------------------
# Host port exposure
# --------------------------------------------------

if [[ -z "$(docker port pp-gitea 2>/dev/null)" ]]; then

    pass "Gitea has no host-published ports"

else

    fail "Gitea has no host-published ports"

fi


# --------------------------------------------------
# Network membership
# --------------------------------------------------

if docker inspect pp-gitea \
    | jq -e '
      .[0].NetworkSettings.Networks
      | has("poisoned-pipeline_control_net")
        and (length == 1)
    ' >/dev/null
then

    pass "Gitea belongs only to control_net"

else

    fail "Gitea belongs only to control_net"

fi


# --------------------------------------------------
# Nginx proxy
# --------------------------------------------------

HTTP_CODE="$(curl \
    -ksS \
    -o /dev/null \
    -w '%{http_code}' \
    https://10.13.10.20/git/ \
    || true)"


case "$HTTP_CODE" in

    200|301|302|303|307|308)

        pass "Gitea reachable through Nginx HTTPS"

        ;;

    *)

        fail "Gitea reachable through Nginx HTTPS ($HTTP_CODE)"

        ;;

esac


# --------------------------------------------------
# Public Git repository
# --------------------------------------------------

if git \
    -c http.sslVerify=false \
    ls-remote \
    https://10.13.10.20/git/nexora/deployment-tools.git \
    >/dev/null 2>&1
then

    pass "S01 repository is anonymously readable"

else

    fail "S01 repository is anonymously readable"

fi


# --------------------------------------------------
# Clone repository
# --------------------------------------------------

WORK_DIR="$(mktemp -d)"

cleanup() {

    rm -rf "$WORK_DIR"

}

trap cleanup EXIT


if git \
    -c http.sslVerify=false \
    clone \
    -q \
    https://10.13.10.20/git/nexora/deployment-tools.git \
    "$WORK_DIR/repository"
then

    pass "S01 repository clone succeeds"

else

    fail "S01 repository clone succeeds"

fi


if [[ ! -d "$WORK_DIR/repository/.git" ]]; then

    echo
    echo "Unable to continue repository checks."
    exit 1

fi


cd "$WORK_DIR/repository"


# --------------------------------------------------
# Current tree must be clean
# --------------------------------------------------

if git grep \
    -E 'IE3132\{PP_S01_|JENKINS_PASSWORD' \
    HEAD -- . \
    >/dev/null 2>&1
then

    fail "Current tree contains no S01 secret"

else

    pass "Current tree contains no S01 secret"

fi


# --------------------------------------------------
# History MUST contain designed disclosure
# --------------------------------------------------

if git log -p --all \
    | grep -q 'S01_FLAG=IE3132{PP_S01_'
then

    pass "Git history contains S01 historical disclosure"

else

    fail "Git history contains S01 historical disclosure"

fi


if git log -p --all \
    | grep -q 'JENKINS_PASSWORD='
then

    pass "Git history contains Jenkins handoff credential"

else

    fail "Git history contains Jenkins handoff credential"

fi


# --------------------------------------------------
# Baseline
# --------------------------------------------------

if [[ -f "$BASELINE" ]]; then

    # shellcheck disable=SC1090
    source "$BASELINE"

    CURRENT_HEAD="$(git rev-parse HEAD)"

    CURRENT_COUNT="$(git rev-list --count HEAD)"


    if [[ "$CURRENT_HEAD" == "$EXPECTED_HEAD" ]]; then

        pass "Repository HEAD matches baseline"

    else

        fail "Repository HEAD matches baseline"

    fi


    if [[ "$CURRENT_COUNT" == "$EXPECTED_COMMIT_COUNT" ]]; then

        pass "Repository commit count matches baseline"

    else

        fail "Repository commit count matches baseline"

    fi

else

    fail "Private S01 baseline exists"

fi


echo
echo "======================================================"
echo " RESULTS"
echo "======================================================"
echo

echo "Passed: $PASS"
echo "Failed: $FAIL"
echo


if [[ "$FAIL" -eq 0 ]]; then

    echo -e "${GREEN}PHASE 6 S01: PASSED${RESET}"

    exit 0

else

    echo -e "${RED}PHASE 6 S01: FAILED${RESET}"

    exit 1

fi