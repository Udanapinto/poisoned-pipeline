#!/usr/bin/env bash

set -u

PASS=0
FAIL=0

green="\033[0;32m"
red="\033[0;31m"
yellow="\033[1;33m"
reset="\033[0m"

pass() {
    echo -e "${green}[PASS]${reset} $1"
    PASS=$((PASS + 1))
}

fail() {
    echo -e "${red}[FAIL]${reset} $1"
    FAIL=$((FAIL + 1))
}

info() {
    echo -e "${yellow}[INFO]${reset} $1"
}

expect_success() {

    description="$1"
    shift

    if "$@" >/dev/null 2>&1; then
        pass "$description"
    else
        fail "$description"
    fi
}

expect_failure() {

    description="$1"
    shift

    if "$@" >/dev/null 2>&1; then
        fail "$description"
    else
        pass "$description"
    fi
}

echo
echo "================================================="
echo " Operation Poisoned Pipeline"
echo " Phase 4 Network Verification"
echo "================================================="
echo

# -------------------------------------------------
# Check Docker networks
# -------------------------------------------------

info "Checking Docker networks..."

expect_success \
    "player_net exists" \
    docker network inspect poisoned-pipeline_player_net

expect_success \
    "control_net exists" \
    docker network inspect poisoned-pipeline_control_net

expect_success \
    "internal_net exists" \
    docker network inspect poisoned-pipeline_internal_net


# -------------------------------------------------
# Intended connections
# -------------------------------------------------

echo
info "Checking intended connectivity..."

expect_success \
    "Kali can reach Application on player_net" \
    docker exec pp-phase4-kali \
    ping -c 1 -W 1 10.13.10.30

expect_success \
    "Application can reach Database on internal_net" \
    docker exec pp-phase4-application \
    ping -c 1 -W 1 10.13.20.10


# -------------------------------------------------
# Forbidden connections
# -------------------------------------------------

echo
info "Checking forbidden connectivity..."

expect_failure \
    "Kali cannot directly reach Database" \
    docker exec pp-phase4-kali \
    ping -c 1 -W 1 10.13.20.10

expect_failure \
    "Kali cannot resolve/reach control container" \
    docker exec pp-phase4-kali \
    ping -c 1 -W 1 pp-phase4-control


# -------------------------------------------------
# Internet isolation
# -------------------------------------------------

echo
info "Checking protected-network external isolation..."

expect_failure \
    "Database cannot directly reach Internet" \
    docker exec pp-phase4-database \
    ping -c 1 -W 1 1.1.1.1

expect_failure \
    "Control container cannot directly reach Internet" \
    docker exec pp-phase4-control \
    ping -c 1 -W 1 1.1.1.1


# -------------------------------------------------
# Final report
# -------------------------------------------------

echo
echo "================================================="
echo " RESULTS"
echo "================================================="
echo
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo

if [ "$FAIL" -eq 0 ]; then

    echo -e "${green}PHASE 4 NETWORK TEST: PASSED${reset}"
    exit 0

else

    echo -e "${red}PHASE 4 NETWORK TEST: FAILED${reset}"
    exit 1

fi