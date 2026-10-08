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
echo " Isolation Sweep"
echo "======================================================"
echo

# --- Network existence ---
for NET in poisoned-pipeline_player_net poisoned-pipeline_control_net poisoned-pipeline_internal_net; do
    if docker network inspect "${NET}" >/dev/null 2>&1; then
        pass "Network exists: ${NET}"
    else
        fail "Network exists: ${NET}"
    fi
done

# --- Network internal flags ---
for NET in poisoned-pipeline_control_net poisoned-pipeline_internal_net; do
    INTERNAL="$(docker network inspect "${NET}" --format '{{.Internal}}' 2>/dev/null || true)"
    if [[ "${INTERNAL}" == "true" ]]; then
        pass "Network ${NET} is internal"
    else
        fail "Network ${NET} is internal (got ${INTERNAL})"
    fi
done

# --- Subnet verification ---
PLAYER_SUBNET="$(docker network inspect poisoned-pipeline_player_net --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null || true)"
if [[ "${PLAYER_SUBNET}" == "10.13.10.0/24" ]]; then
    pass "player_net subnet is 10.13.10.0/24"
else
    fail "player_net subnet is 10.13.10.0/24 (got ${PLAYER_SUBNET})"
fi

INTERNAL_SUBNET="$(docker network inspect poisoned-pipeline_internal_net --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null || true)"
if [[ "${INTERNAL_SUBNET}" == "10.13.20.0/24" ]]; then
    pass "internal_net subnet is 10.13.20.0/24"
else
    fail "internal_net subnet is 10.13.20.0/24 (got ${INTERNAL_SUBNET})"
fi

# --- Container network membership (expected) ---
declare -A EXPECTED
EXPECTED[pp-kali]="player_net"
EXPECTED[pp-nginx]="player_net,control_net"
EXPECTED[pp-ctfd]="control_net"
EXPECTED[pp-mariadb]="control_net"
EXPECTED[pp-redis]="control_net"
EXPECTED[pp-gitea]="control_net"
EXPECTED[pp-jenkins]="control_net"
EXPECTED[pp-application]="player_net,internal_net"
EXPECTED[pp-postgres]="internal_net"

for CONTAINER in "${!EXPECTED[@]}"; do
    NETS="$(docker inspect --format '{{json .NetworkSettings.Networks}}' "${CONTAINER}" 2>/dev/null || true)"
    EXPECTED_NETS="${EXPECTED[$CONTAINER]}"

    for NET in $(echo "${EXPECTED_NETS}" | tr ',' ' '); do
        if grep -q "poisoned-pipeline_${NET}" <<<"${NETS}"; then
            pass "${CONTAINER} is on ${NET}"
        else
            fail "${CONTAINER} is on ${NET}"
        fi
    done
done

# --- Forbidden memberships ---
# Only Kali and control-layer services must NOT be on internal_net.
# PostgreSQL IS on internal_net by design, so it is excluded here.
for CONTAINER in pp-kali pp-ctfd pp-mariadb pp-redis pp-gitea pp-jenkins; do
    NETS="$(docker inspect --format '{{json .NetworkSettings.Networks}}' "${CONTAINER}" 2>/dev/null || true)"
    if grep -q 'poisoned-pipeline_internal_net' <<<"${NETS}"; then
        fail "${CONTAINER} is NOT on internal_net"
    else
        pass "${CONTAINER} is NOT on internal_net"
    fi
done

# --- Published ports ---
for CONTAINER in pp-mariadb pp-redis pp-ctfd pp-gitea pp-jenkins pp-postgres pp-application pp-kali; do
    PORTS="$(docker port "${CONTAINER}" 2>/dev/null || true)"
    if [[ -z "${PORTS}" ]]; then
        pass "${CONTAINER} has no host-published ports"
    else
        fail "${CONTAINER} has no host-published ports"
    fi
done

NGINX_PORTS="$(docker port pp-nginx 2>/dev/null || true)"
if grep -q '443' <<<"${NGINX_PORTS}"; then
    pass "Nginx publishes TCP 443"
else
    fail "Nginx publishes TCP 443"
fi

# --- Privileged mode ---
for CONTAINER in pp-kali pp-application pp-postgres pp-ctfd pp-gitea pp-jenkins pp-mariadb pp-redis; do
    PRIV="$(docker inspect --format '{{.HostConfig.Privileged}}' "${CONTAINER}" 2>/dev/null || true)"
    if [[ "${PRIV}" == "false" ]]; then
        pass "${CONTAINER} is not privileged"
    else
        fail "${CONTAINER} is not privileged"
    fi
done

# --- Host PID/network namespace ---
for CONTAINER in pp-kali pp-application pp-postgres; do
    PID_MODE="$(docker inspect --format '{{.HostConfig.PidMode}}' "${CONTAINER}" 2>/dev/null || true)"
    NET_MODE="$(docker inspect --format '{{.HostConfig.NetworkMode}}' "${CONTAINER}" 2>/dev/null || true)"
    if [[ "${PID_MODE}" != "host" ]]; then
        pass "${CONTAINER} does not use host PID namespace"
    else
        fail "${CONTAINER} does not use host PID namespace"
    fi
    if [[ "${NET_MODE}" != "host" ]]; then
        pass "${CONTAINER} does not use host network mode"
    else
        fail "${CONTAINER} does not use host network mode"
    fi
done

# --- Docker socket absence ---
for CONTAINER in pp-kali pp-application pp-postgres pp-ctfd pp-gitea pp-jenkins; do
    if docker inspect "${CONTAINER}" 2>/dev/null | grep -Fq '/var/run/docker.sock'; then
        fail "${CONTAINER} has no Docker socket"
    else
        pass "${CONTAINER} has no Docker socket"
    fi
done

# --- Intended connectivity ---
if docker exec pp-kali curl -fsS http://10.13.10.30:5000/healthz >/dev/null 2>&1; then
    pass "Kali -> Application TCP 5000 works"
else
    fail "Kali -> Application TCP 5000 works"
fi

# Application -> PostgreSQL: use TCP check on port 5432
# (netcat is installed; ping is not)
if docker exec pp-application nc -z -w 3 10.13.20.10 5432 >/dev/null 2>&1; then
    pass "Application -> PostgreSQL internal_net TCP 5432 works"
else
    fail "Application -> PostgreSQL internal_net TCP 5432 works"
fi

# --- Forbidden connectivity ---
if docker exec pp-kali nc -z -w 3 10.13.20.10 5432 >/dev/null 2>&1; then
    fail "Kali -> PostgreSQL directly fails"
else
    pass "Kali -> PostgreSQL directly fails"
fi

if docker exec pp-kali nc -z -w 3 pp-gitea 3000 >/dev/null 2>&1; then
    fail "Kali -> Gitea directly fails"
else
    pass "Kali -> Gitea directly fails"
fi

if docker exec pp-kali nc -z -w 3 pp-jenkins 8080 >/dev/null 2>&1; then
    fail "Kali -> Jenkins directly fails"
else
    pass "Kali -> Jenkins directly fails"
fi

# --- External egress isolation ---
for CONTAINER in pp-ctfd pp-gitea pp-jenkins pp-application pp-postgres; do
    if docker exec "${CONTAINER}" sh -lc 'nc -z -w 3 1.1.1.1 443' >/dev/null 2>&1; then
        fail "${CONTAINER} cannot reach the Internet"
    else
        pass "${CONTAINER} cannot reach the Internet"
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
    echo "ISOLATION SWEEP: PASSED"
    exit 0
else
    echo "ISOLATION SWEEP: FAILED"
    exit 1
fi