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
echo " Clean Deploy Verification"
echo "======================================================"
echo

# --- Validate compose configuration ---
if docker compose config -q 2>/dev/null; then
    pass "Docker Compose configuration is valid"
else
    fail "Docker Compose configuration is valid"
fi

# --- All expected services are defined ---
SERVICES="$(docker compose config --services 2>/dev/null || true)"
for SVC in mariadb redis ctfd gitea jenkins postgres application kali nginx; do
    if grep -qx "${SVC}" <<<"${SERVICES}"; then
        pass "Service defined: ${SVC}"
    else
        fail "Service defined: ${SVC}"
    fi
done

# --- All expected networks are defined ---
NETWORKS="$(docker compose config --networks 2>/dev/null || true)"
for NET in player_net control_net internal_net; do
    if grep -qx "${NET}" <<<"${NETWORKS}"; then
        pass "Network defined: ${NET}"
    else
        fail "Network defined: ${NET}"
    fi
done

# --- All expected volumes are defined ---
VOLUMES="$(docker compose config --volumes 2>/dev/null || true)"
for VOL in mariadb_data redis_data ctfd_uploads ctfd_logs gitea_data jenkins_data postgres_data; do
    if grep -qx "${VOL}" <<<"${VOLUMES}"; then
        pass "Volume defined: ${VOL}"
    else
        fail "Volume defined: ${VOL}"
    fi
done

# --- No floating latest tags (excluding Kali base) ---
CONFIG="$(docker compose config 2>/dev/null || true)"
if grep -E 'image:.*:latest' <<<"${CONFIG}" | grep -v 'kali-rolling' >/dev/null 2>&1; then
    fail "No floating latest tags (excluding Kali base)"
else
    pass "No floating latest tags (excluding Kali base)"
fi

# --- All containers healthy ---
for SVC in pp-mariadb pp-redis pp-ctfd pp-gitea pp-jenkins pp-postgres pp-application pp-kali pp-nginx; do
    RUNNING="$(docker inspect --format '{{.State.Running}}' "${SVC}" 2>/dev/null || true)"
    if [[ "${RUNNING}" == "true" ]]; then
        pass "${SVC} is running"
    else
        fail "${SVC} is running"
    fi
done

echo
echo "======================================================"
echo " RESULTS"
echo "======================================================"
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"
echo

if [[ "${FAIL}" -eq 0 ]]; then
    echo "CLEAN DEPLOY: PASSED"
    exit 0
else
    echo "CLEAN DEPLOY: FAILED"
    exit 1
fi
