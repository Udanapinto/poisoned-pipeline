#!/usr/bin/env bash

set -u

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


check_running() {

    CONTAINER="$1"
    DESCRIPTION="$2"

    RESULT="$(docker inspect \
        -f '{{.State.Running}}' \
        "$CONTAINER" \
        2>/dev/null || true)"

    if [[ "$RESULT" == "true" ]]; then

        pass "$DESCRIPTION"

    else

        fail "$DESCRIPTION"

    fi

}


check_healthy() {

    CONTAINER="$1"
    DESCRIPTION="$2"

    RESULT="$(docker inspect \
        -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' \
        "$CONTAINER" \
        2>/dev/null || true)"

    if [[ "$RESULT" == "healthy" ]]; then

        pass "$DESCRIPTION"

    else

        fail "$DESCRIPTION (status=$RESULT)"

    fi

}


check_no_published_ports() {

    CONTAINER="$1"
    DESCRIPTION="$2"

    OUTPUT="$(docker port "$CONTAINER" 2>/dev/null || true)"

    if [[ -z "$OUTPUT" ]]; then

        pass "$DESCRIPTION"

    else

        fail "$DESCRIPTION"

        echo "$OUTPUT"

    fi

}


echo
echo "======================================================"
echo " Operation Poisoned Pipeline"
echo " Phase 5 - Control Stack Verification"
echo "======================================================"
echo


# ==========================================================
# Containers
# ==========================================================

info "Checking container state..."

check_running \
    "pp-mariadb" \
    "MariaDB container is running"

check_running \
    "pp-redis" \
    "Redis container is running"

check_running \
    "pp-ctfd" \
    "CTFd container is running"

check_running \
    "pp-nginx" \
    "Nginx container is running"


echo


# ==========================================================
# Health
# ==========================================================

info "Checking health status..."

check_healthy \
    "pp-mariadb" \
    "MariaDB is healthy"

check_healthy \
    "pp-redis" \
    "Redis is healthy"

check_healthy \
    "pp-ctfd" \
    "CTFd is healthy"


echo


# ==========================================================
# Backend port exposure
# ==========================================================

info "Checking backend host exposure..."

check_no_published_ports \
    "pp-mariadb" \
    "MariaDB has no host-published ports"

check_no_published_ports \
    "pp-redis" \
    "Redis has no host-published ports"

check_no_published_ports \
    "pp-ctfd" \
    "CTFd has no host-published ports"


echo


# ==========================================================
# Nginx HTTPS
# ==========================================================

info "Checking Nginx participant entry point..."

if docker port pp-nginx 443/tcp \
    2>/dev/null \
    | grep -q "443"; then

    pass "Nginx publishes TCP 443"

else

    fail "Nginx publishes TCP 443"

fi


HTTP_CODE="$(curl \
    -ksS \
    --connect-timeout 5 \
    -o /dev/null \
    -w '%{http_code}' \
    https://127.0.0.1/ \
    || true)"

case "$HTTP_CODE" in

    200|301|302|303|307|308)

        pass "CTFd is reachable through Nginx HTTPS ($HTTP_CODE)"

        ;;

    *)

        fail "CTFd HTTPS response ($HTTP_CODE)"

        ;;

esac


echo


# ==========================================================
# Internal service connectivity
# ==========================================================

info "Checking CTFd backend connectivity..."

if docker exec pp-ctfd python -c '
import socket
socket.create_connection(("mariadb",3306),3).close()
socket.create_connection(("redis",6379),3).close()
' >/dev/null 2>&1; then

    pass "CTFd can reach MariaDB and Redis"

else

    fail "CTFd can reach MariaDB and Redis"

fi


echo


# ==========================================================
# Network membership
# ==========================================================

info "Checking network membership..."

if docker inspect pp-ctfd \
    | jq -e '
        .[0].NetworkSettings.Networks
        | has("poisoned-pipeline_control_net")
          and (length == 1)
    ' >/dev/null; then

    pass "CTFd belongs only to control_net"

else

    fail "CTFd belongs only to control_net"

fi


if docker inspect pp-mariadb \
    | jq -e '
        .[0].NetworkSettings.Networks
        | has("poisoned-pipeline_control_net")
          and (length == 1)
    ' >/dev/null; then

    pass "MariaDB belongs only to control_net"

else

    fail "MariaDB belongs only to control_net"

fi


if docker inspect pp-redis \
    | jq -e '
        .[0].NetworkSettings.Networks
        | has("poisoned-pipeline_control_net")
          and (length == 1)
    ' >/dev/null; then

    pass "Redis belongs only to control_net"

else

    fail "Redis belongs only to control_net"

fi


if docker inspect pp-nginx \
    | jq -e '
        .[0].NetworkSettings.Networks
        | has("poisoned-pipeline_control_net")
          and has("poisoned-pipeline_player_net")
          and
          .["poisoned-pipeline_player_net"].IPAddress
              == "10.13.10.20"
          and
          (length == 2)
    ' >/dev/null; then

    pass "Nginx correctly spans player_net and control_net"

else

    fail "Nginx network configuration"

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

    echo -e \
        "${GREEN}PHASE 5 CONTROL STACK: PASSED${RESET}"

    exit 0

else

    echo -e \
        "${RED}PHASE 5 CONTROL STACK: FAILED${RESET}"

    exit 1

fi