#!/usr/bin/env bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

CONTAINER="pp-application"

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

echo "======================================================"
echo " Operation Poisoned Pipeline"
echo " Phase 9 - Application Challenge Verification"
echo "======================================================"
echo

# --------------------------------------------------
# Container state
# --------------------------------------------------
if docker inspect "$CONTAINER" >/dev/null 2>&1; then
    pass "Application container exists"
else
    fail "Application container exists"
fi

RUNNING="$(
    docker inspect \
    --format '{{.State.Running}}' \
    "$CONTAINER" \
    2>/dev/null || true
)"

if [[ "$RUNNING" == "true" ]]; then
    pass "Application container is running"
else
    fail "Application container is running"
fi

HEALTH="$(
    docker inspect \
    --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' \
    "$CONTAINER" \
    2>/dev/null || true
)"

if [[ "$HEALTH" == "healthy" ]]; then
    pass "Application healthcheck is healthy"
else
    fail "Application healthcheck is healthy"
fi

# --------------------------------------------------
# Runtime versions
# --------------------------------------------------
PY_VERSION="$(
    docker compose exec -T application \
    python -c \
    'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' \
    2>/dev/null \
    | tr -d '\r'
)"

if [[ "$PY_VERSION" == "3.9" ]]; then
    pass "Python runtime is 3.9"
else
    fail "Python runtime is 3.9"
fi

FLASK_VERSION="$(
    docker compose exec -T application \
    python -c \
    'import importlib.metadata as m; print(m.version("flask"))' \
    2>/dev/null \
    | tr -d '\r'
)"

if [[ "$FLASK_VERSION" == 3.* ]]; then
    pass "Flask runtime is 3.x"
else
    fail "Flask runtime is 3.x"
fi

# --------------------------------------------------
# Service identity
# --------------------------------------------------
PID1_UID="$(
    docker compose exec -T application \
    sh -lc \
    "awk '/^Uid:/{print \$2}' /proc/1/status" \
    2>/dev/null \
    | tr -d '\r'
)"

if [[ "$PID1_UID" == "10001" ]]; then
    pass "Flask PID 1 runs as UID 10001"
else
    fail "Flask PID 1 runs as UID 10001"
fi

ACCOUNT="$(
    docker compose exec -T application \
    getent passwd 10001 \
    2>/dev/null \
    | cut -d: -f1 \
    | tr -d '\r'
)"

if [[ "$ACCOUNT" == "pipeline-app" ]]; then
    pass "UID 10001 belongs to pipeline-app"
else
    fail "UID 10001 belongs to pipeline-app"
fi

CAP_EFF="$(
    docker compose exec -T application \
    sh -lc \
    "awk '/^CapEff:/{print \$2}' /proc/1/status" \
    2>/dev/null \
    | tr -d '\r'
)"

if [[ "$CAP_EFF" == "0000000000000000" ]]; then
    pass "Flask process has no effective Linux capabilities"
else
    fail "Flask process has no effective Linux capabilities"
fi

# --------------------------------------------------
# Host identity / S03 handoff
# --------------------------------------------------
HOSTNAME="$(
    docker compose exec -T application \
    hostname \
    2>/dev/null \
    | tr -d '\r'
)"

if [[ "$HOSTNAME" == "nexora-app" ]]; then
    pass "Application hostname matches S03 target"
else
    fail "Application hostname matches S03 target"
fi

STATUS_JSON="$(
    docker compose exec -T application \
    curl -fsS \
    http://127.0.0.1:5000/api/status \
    2>/dev/null || true
)"

STATUS_VERSION="$(
    jq -r '.version // empty' <<< "$STATUS_JSON"
)"

STATUS_HOST="$(
    jq -r '.host // empty' <<< "$STATUS_JSON"
)"

if [[ "$STATUS_VERSION" == "nexora-platform-2026.09.03" ]]; then
    pass "Application version matches S03 handoff"
else
    fail "Application version matches S03 handoff"
fi

if [[ "$STATUS_HOST" == "nexora-app" ]]; then
    pass "API host matches S03 target"
else
    fail "API host matches S03 target"
fi

# --------------------------------------------------
# HTTP service
# --------------------------------------------------
if docker compose exec -T application \
    curl -fsS \
    http://127.0.0.1:5000/healthz \
    >/dev/null 2>&1
then
    pass "TCP 5000 Flask health endpoint works"
else
    fail "TCP 5000 Flask health endpoint works"
fi

DIAG_CODE="$(
    docker compose exec -T application \
    curl -sS \
    -o /dev/null \
    -w '%{http_code}' \
    -X POST \
    http://127.0.0.1:5000/api/diagnostics/run \
    2>/dev/null || true
)"

if [[ "$DIAG_CODE" == "404" ]]; then
    pass "S04 diagnostics endpoint is absent in Phase 9"
else
    fail "S04 diagnostics endpoint is absent in Phase 9"
fi

# --------------------------------------------------
# Network addresses
# --------------------------------------------------
PLAYER_IP="$(
    docker inspect \
    "$CONTAINER" \
    --format \
    '{{(index .NetworkSettings.Networks "poisoned-pipeline_player_net").IPAddress}}' \
    2>/dev/null
)"

INTERNAL_IP="$(
    docker inspect \
    "$CONTAINER" \
    --format \
    '{{(index .NetworkSettings.Networks "poisoned-pipeline_internal_net").IPAddress}}' \
    2>/dev/null
)"

if [[ "$PLAYER_IP" == "10.13.10.30" ]]; then
    pass "player_net address is 10.13.10.30"
else
    fail "player_net address is 10.13.10.30"
fi

if [[ "$INTERNAL_IP" == "10.13.20.1" ]]; then
    pass "internal_net address is 10.13.20.1"
else
    fail "internal_net address is 10.13.20.1"
fi

# --------------------------------------------------
# Published ports
# --------------------------------------------------
PORTS="$(docker port "$CONTAINER" 2>/dev/null || true)"

if [[ -z "$PORTS" ]]; then
    pass "Application has no host-published ports"
else
    fail "Application has no host-published ports"
fi

# --------------------------------------------------
# SSH must not be enabled yet
# --------------------------------------------------
if docker compose exec -T application \
    sh -lc \
    'ss -lntH | awk "{print \$4}" | grep -Eq "(^|:)22$"' \
    >/dev/null 2>&1
then
    fail "SSH is not listening in Phase 9"
else
    pass "SSH is not listening in Phase 9"
fi

# --------------------------------------------------
# S05 privilege path must not exist yet
# --------------------------------------------------
if docker compose exec \
    -T \
    --user 10001:10001 \
    application \
    sudo -n -l \
    >/dev/null 2>&1
then
    fail "No Phase 9 passwordless sudo path exists"
else
    pass "No Phase 9 passwordless sudo path exists"
fi

# --------------------------------------------------
# Container security
# --------------------------------------------------
PRIVILEGED="$(
    docker inspect \
    "$CONTAINER" \
    --format '{{.HostConfig.Privileged}}' \
    2>/dev/null
)"

if [[ "$PRIVILEGED" == "false" ]]; then
    pass "Container is not privileged"
else
    fail "Container is not privileged"
fi

PID_MODE="$(
    docker inspect \
    "$CONTAINER" \
    --format '{{.HostConfig.PidMode}}' \
    2>/dev/null
)"

if [[ "$PID_MODE" != "host" ]]; then
    pass "Host PID namespace is not used"
else
    fail "Host PID namespace is not used"
fi

NETWORK_MODE="$(
    docker inspect \
    "$CONTAINER" \
    --format '{{.HostConfig.NetworkMode}}' \
    2>/dev/null
)"

if [[ "$NETWORK_MODE" != "host" ]]; then
    pass "Host network mode is not used"
else
    fail "Host network mode is not used"
fi

if docker inspect "$CONTAINER" \
    | grep -Fq '/var/run/docker.sock'
then
    fail "Docker socket is absent"
else
    pass "Docker socket is absent"
fi

MOUNT_COUNT="$(
    docker inspect \
    "$CONTAINER" \
    --format '{{len .Mounts}}' \
    2>/dev/null
)"

if [[ "$MOUNT_COUNT" == "0" ]]; then
    pass "Application has no host mounts"
else
    fail "Application has no host mounts"
fi

# --------------------------------------------------
# External egress containment
#
# The container may still contain a kernel route,
# but Docker/host egress policy must prevent actual
# outbound connectivity.
# --------------------------------------------------

if docker compose exec -T application \
    sh -lc \
    'nc -z -w 3 1.1.1.1 443 >/dev/null 2>&1'
then
    fail "External Internet egress is blocked"
else
    pass "External Internet egress is blocked"
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
    echo "PHASE 9 APPLICATION: PASSED"
    exit 0
else
    echo "PHASE 9 APPLICATION: FAILED"
    exit 1
fi