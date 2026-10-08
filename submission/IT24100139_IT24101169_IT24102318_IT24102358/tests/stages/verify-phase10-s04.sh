#!/usr/bin/env bash
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

CONTAINER="pp-application"
TARGET_URL="http://127.0.0.1:5000"

PASS=0
FAIL=0

pass() { echo "[PASS] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

echo "=============================================="
echo " Operation Poisoned Pipeline"
echo " Phase 10 - S04 Poisoned Runtime Verification"
echo "=============================================="
echo

# ------------------------------------------------------
# Container state
# ------------------------------------------------------
if docker inspect "${CONTAINER}" >/dev/null 2>&1; then
  pass "Application container exists"
else
  fail "Application container exists"
fi

RUNNING="$(docker inspect --format '{{.State.Running}}' "${CONTAINER}" 2>/dev/null || true)"
if [[ "${RUNNING}" == "true" ]]; then
  pass "Application container is running"
else
  fail "Application container is running"
fi

HEALTH="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}unknown{{end}}' "${CONTAINER}" 2>/dev/null || true)"
if [[ "${HEALTH}" == "healthy" ]]; then
  pass "Application healthcheck is healthy"
else
  fail "Application healthcheck is healthy (status=${HEALTH})"
fi

# ------------------------------------------------------
# Vulnerable endpoint reachable
# ------------------------------------------------------
CODE="$(docker compose exec -T application \
  curl -sS -o /dev/null -w '%{http_code}' \
  -X POST \
  -H 'Content-Type: application/json' \
  -d '{"component":"nexora-utils"}' \
  "${TARGET_URL}/api/diagnostics/run" 2>/dev/null || true)"

if [[ "${CODE}" == "200" ]]; then
  pass "S04 diagnostics endpoint responds with 200"
else
  fail "S04 diagnostics endpoint responds with 200 (got ${CODE})"
fi

# ------------------------------------------------------
# Controlled command execution as pipeline-app
# ------------------------------------------------------
OUT="$(docker compose exec -T application \
  curl -sS \
  -H 'Content-Type: application/json' \
  -d '{"component":"nexora-utils; id","verbose":true}' \
  "${TARGET_URL}/api/diagnostics/run" 2>/dev/null \
  | jq -r '.stdout // empty' 2>/dev/null || true)"

if grep -q 'uid=10001(pipeline-app)' <<< "${OUT}"; then
  pass "Injected command executes as pipeline-app (UID 10001)"
else
  fail "Injected command executes as pipeline-app (UID 10001)"
fi

if grep -q 'uid=0(root)' <<< "${OUT}"; then
  fail "Injected command does not run as root"
else
  pass "Injected command does not run as root"
fi

# ------------------------------------------------------
# S04 flag file
# ------------------------------------------------------
source private/s04/s04.env

FLAG_OUT="$(docker compose exec -T application \
  curl -sS \
  -H 'Content-Type: application/json' \
  -d '{"component":"nexora-utils; cat /opt/nexora/private/s04_flag.txt","verbose":true}' \
  "${TARGET_URL}/api/diagnostics/run" 2>/dev/null \
  | jq -r '.stdout // empty' 2>/dev/null \
  | grep -oE 'IE3132\{PP_S04_[0-9a-f]{32}\}' \
  | head -n 1 || true)"

if [[ "${FLAG_OUT}" == "${S04_FLAG}" ]]; then
  pass "Injected command recovers the expected S04 flag"
else
  fail "Injected command recovers the expected S04 flag"
fi

if [[ "${S04_FLAG}" =~ ^IE3132\{PP_S04_[0-9a-f]{32}\}$ ]]; then
  pass "S04 flag format is IE3132{PP_S04_<32 hex>}"
else
  fail "S04 flag format is IE3132{PP_S04_<32 hex>}"
fi

# ------------------------------------------------------
# S05 handoff clue
# ------------------------------------------------------
HANDOFF_OUT="$(docker compose exec -T application \
  sh -lc 'cat /opt/nexora/config/deployment.conf 2>/dev/null' || true)"

if grep -q 'deploy_verify_binary=/usr/local/bin/deploy-verify' <<< "${HANDOFF_OUT}"; then
  pass "S05 handoff clue references deploy-verify"
else
  fail "S05 handoff clue references deploy-verify"
fi

if grep -q 'validation_hook=' <<< "${HANDOFF_OUT}"; then
  pass "S05 handoff clue references the trusted hook path"
else
  fail "S05 handoff clue references the trusted hook path"
fi

# ------------------------------------------------------
# S05 and S06 secrets are NOT present
# ------------------------------------------------------
if docker compose exec -T application \
    sh -lc 'test -f /opt/nexora/private/s05_flag.txt' >/dev/null 2>&1; then
  fail "S05 flag is not present in Phase 10"
else
  pass "S05 flag is not present in Phase 10"
fi

if docker compose exec -T application \
    sh -lc 'test -f /opt/nexora/private/s06_flag.txt' >/dev/null 2>&1; then
  fail "S06 flag is not present in Phase 10"
else
  pass "S06 flag is not present in Phase 10"
fi

# ------------------------------------------------------
# Privilege boundary inside the container
# ------------------------------------------------------
PID1_UID="$(docker compose exec -T application \
  sh -lc "awk '/^Uid:/{print \$2}' /proc/1/status" 2>/dev/null | tr -d '\r' || true)"

if [[ "${PID1_UID}" == "10001" ]]; then
  pass "Flask PID 1 still runs as UID 10001"
else
  fail "Flask PID 1 still runs as UID 10001 (got ${PID1_UID})"
fi

CAP_EFF="$(docker compose exec -T application \
  sh -lc "awk '/^CapEff:/{print \$2}' /proc/1/status" 2>/dev/null | tr -d '\r' || true)"

if [[ "${CAP_EFF}" == "0000000000000000" ]]; then
  pass "Flask process still has no effective Linux capabilities"
else
  fail "Flask process still has no effective Linux capabilities"
fi

# --- Phase 12 SSH pivot endpoint must be listening ---
if docker compose exec -T application \
    sh -lc 'ss -lntH | awk "{print \$4}" | grep -Eq "(^|:)22\$"' >/dev/null 2>&1; then
    pass "SSH is listening on TCP 22 (Phase 12 state)"
else
    fail "SSH is listening on TCP 22 (Phase 12 state)"
fi

# --- Phase 11 passwordless sudo exists ONLY for deploy-verify ---
SUDO_LIST="$(docker compose exec -T --user 10001:10001 application sh -lc 'sudo -n -l' 2>/dev/null || true)"

if grep -q '/usr/local/bin/deploy-verify' <<<"${SUDO_LIST}"; then
    pass "Passwordless sudo exists for /usr/local/bin/deploy-verify (Phase 11 state)"
else
    fail "Passwordless sudo exists for /usr/local/bin/deploy-verify (Phase 11 state)"
fi

if grep -qE 'NOPASSWD:.*/bin/bash' <<<"${SUDO_LIST}"; then
    fail "Passwordless sudo does NOT allow /bin/bash"
else
    pass "Passwordless sudo does NOT allow /bin/bash"
fi

if grep -qE 'NOPASSWD:.*/bin/sh' <<<"${SUDO_LIST}"; then
    fail "Passwordless sudo does NOT allow /bin/sh"
else
    pass "Passwordless sudo does NOT allow /bin/sh"
fi

if grep -qE 'NOPASSWD:.*/usr/bin/python' <<<"${SUDO_LIST}"; then
    fail "Passwordless sudo does NOT allow python"
else
    pass "Passwordless sudo does NOT allow python"
fi

# ------------------------------------------------------
# Container security configuration
# ------------------------------------------------------
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
if [[ "${MOUNT_COUNT}" == "0" ]]; then
  pass "Application has no host mounts"
else
  fail "Application has no host mounts"
fi

# ------------------------------------------------------
# Network addressing
# ------------------------------------------------------
PLAYER_IP="$(docker inspect \
  --format '{{(index .NetworkSettings.Networks "poisoned-pipeline_player_net").IPAddress}}' \
  "${CONTAINER}" 2>/dev/null || true)"

INTERNAL_IP="$(docker inspect \
  --format '{{(index .NetworkSettings.Networks "poisoned-pipeline_internal_net").IPAddress}}' \
  "${CONTAINER}" 2>/dev/null || true)"

if [[ "${PLAYER_IP}" == "10.13.10.30" ]]; then
  pass "player_net address is 10.13.10.30"
else
  fail "player_net address is 10.13.10.30 (got ${PLAYER_IP})"
fi

if [[ "${INTERNAL_IP}" == "10.13.20.1" ]]; then
  pass "internal_net address is 10.13.20.1"
else
  fail "internal_net address is 10.13.20.1 (got ${INTERNAL_IP})"
fi

PORTS="$(docker port "${CONTAINER}" 2>/dev/null || true)"
if [[ -z "${PORTS}" ]]; then
  pass "Application has no host-published ports"
else
  fail "Application has no host-published ports"
fi

echo
echo "=============================================="
echo " RESULTS"
echo "=============================================="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"
echo

if [[ "${FAIL}" -eq 0 ]]; then
  echo "PHASE 10 S04: PASSED"
  exit 0
else
  echo "PHASE 10 S04: FAILED"
  exit 1
fi
