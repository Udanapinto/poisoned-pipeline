#!/usr/bin/env bash
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

CONTAINER="pp-kali"

PASS=0
FAIL=0

pass() { echo "[PASS] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

echo "======================================================"
echo " Operation Poisoned Pipeline"
echo " Phase 13 - Kali Participant Verification"
echo "======================================================"
echo

# --- Container state ---
if docker inspect "${CONTAINER}" >/dev/null 2>&1; then
    pass "Kali container exists"
else
    fail "Kali container exists"
fi

RUNNING="$(docker inspect --format '{{.State.Running}}' "${CONTAINER}" 2>/dev/null || true)"
if [[ "${RUNNING}" == "true" ]]; then
    pass "Kali container is running"
else
    fail "Kali container is running"
fi

# --- Network membership ---
NETS="$(docker inspect --format '{{json .NetworkSettings.Networks}}' "${CONTAINER}" 2>/dev/null || true)"

if grep -q 'poisoned-pipeline_player_net' <<<"${NETS}"; then
    pass "Kali is on player_net"
else
    fail "Kali is on player_net"
fi

if grep -q 'poisoned-pipeline_control_net' <<<"${NETS}"; then
    fail "Kali is NOT on control_net"
else
    pass "Kali is NOT on control_net"
fi

if grep -q 'poisoned-pipeline_internal_net' <<<"${NETS}"; then
    fail "Kali is NOT on internal_net"
else
    pass "Kali is NOT on internal_net"
fi

PLAYER_IP="$(docker inspect --format '{{(index .NetworkSettings.Networks "poisoned-pipeline_player_net").IPAddress}}' "${CONTAINER}" 2>/dev/null || true)"
if [[ "${PLAYER_IP}" == "10.13.10.10" ]]; then
    pass "Kali player_net address is 10.13.10.10"
else
    fail "Kali player_net address is 10.13.10.10 (got ${PLAYER_IP})"
fi

# --- Tool availability ---
for TOOL in git curl jq python3 nmap proxychains4 ssh psql nc sshpass; do
    if docker exec "${CONTAINER}" sh -lc "command -v ${TOOL}" >/dev/null 2>&1; then
        pass "Tool available: ${TOOL}"
    else
        fail "Tool available: ${TOOL}"
    fi
done

# --- Intended connectivity ---
if docker exec "${CONTAINER}" curl -fsS http://10.13.10.30:5000/healthz >/dev/null 2>&1; then
    pass "Kali can reach Application TCP 5000"
else
    fail "Kali can reach Application TCP 5000"
fi

NGINX_CODE="$(docker exec "${CONTAINER}" curl -kfsS -o /dev/null -w '%{http_code}' https://10.13.10.20/ 2>/dev/null || true)"
if [[ "${NGINX_CODE}" =~ ^(200|301|302|303|307|308)$ ]]; then
    pass "Kali can reach Nginx HTTPS (${NGINX_CODE})"
else
    fail "Kali can reach Nginx HTTPS (got ${NGINX_CODE})"
fi

# --- Forbidden connectivity ---
if docker exec "${CONTAINER}" ping -c 1 -W 1 10.13.20.10 >/dev/null 2>&1; then
    fail "Kali cannot reach PostgreSQL directly"
else
    pass "Kali cannot reach PostgreSQL directly"
fi

if docker exec "${CONTAINER}" ping -c 1 -W 1 pp-gitea >/dev/null 2>&1; then
    fail "Kali cannot reach Gitea directly"
else
    pass "Kali cannot reach Gitea directly"
fi

if docker exec "${CONTAINER}" ping -c 1 -W 1 pp-jenkins >/dev/null 2>&1; then
    fail "Kali cannot reach Jenkins directly"
else
    pass "Kali cannot reach Jenkins directly"
fi

# --- Container security ---
PRIVILEGED="$(docker inspect --format '{{.HostConfig.Privileged}}' "${CONTAINER}" 2>/dev/null || true)"
if [[ "${PRIVILEGED}" == "false" ]]; then
    pass "Container is not privileged"
else
    fail "Container is not privileged"
fi

PID_MODE="$(docker inspect --format '{{.HostConfig.PidMode}}' "${CONTAINER}" 2>/dev/null || true)"
if [[ "${PID_MODE}" != "host" ]]; then
    pass "Host PID namespace is not used"
else
    fail "Host PID namespace is not used"
fi

NET_MODE="$(docker inspect --format '{{.HostConfig.NetworkMode}}' "${CONTAINER}" 2>/dev/null || true)"
if [[ "${NET_MODE}" != "host" ]]; then
    pass "Host network mode is not used"
else
    fail "Host network mode is not used"
fi

if docker inspect "${CONTAINER}" | grep -Fq '/var/run/docker.sock'; then
    fail "Docker socket is absent"
else
    pass "Docker socket is absent"
fi

MOUNT_COUNT="$(docker inspect --format '{{len .Mounts}}' "${CONTAINER}" 2>/dev/null || true)"
if [[ "${MOUNT_COUNT}" -le 2 ]]; then
    pass "Kali has minimal host mounts"
else
    fail "Kali has minimal host mounts (${MOUNT_COUNT})"
fi

echo
echo "======================================================"
echo " RESULTS"
echo "======================================================"
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"
echo

if [[ "${FAIL}" -eq 0 ]]; then
    echo "PHASE 13 KALI: PASSED"
    exit 0
else
    echo "PHASE 13 KALI: FAILED"
    exit 1
fi
