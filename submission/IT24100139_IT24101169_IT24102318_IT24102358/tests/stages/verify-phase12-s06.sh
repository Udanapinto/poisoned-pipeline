#!/usr/bin/env bash
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

S06_FILE="private/s06/s06.env"
APP="pp-application"
PG="pp-postgres"

PASS=0
FAIL=0

pass() { echo "[PASS] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

echo "=============================================================="
echo " Operation Poisoned Pipeline"
echo " Phase 12 - S06 Behind the Firewall Verification"
echo "=============================================================="
echo

if [[ ! -f "${S06_FILE}" ]]; then
  fail "private/s06/s06.env exists"
  echo
  echo "Passed: ${PASS}"
  echo "Failed: ${FAIL}"
  echo "PHASE 12 S06: FAILED"
  exit 1
fi
# shellcheck disable=SC1090
source "${S06_FILE}"
pass "private/s06/s06.env exists"

# ---------------------------------------------------------------
# PostgreSQL container state
# ---------------------------------------------------------------
if docker inspect "${PG}" >/dev/null 2>&1; then
  pass "PostgreSQL container exists"
else
  fail "PostgreSQL container exists"
fi

RUNNING="$(docker inspect --format '{{.State.Running}}' "${PG}" 2>/dev/null || true)"
if [[ "${RUNNING}" == "true" ]]; then
  pass "PostgreSQL container is running"
else
  fail "PostgreSQL container is running"
fi

HEALTH="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}unknown{{end}}' "${PG}" 2>/dev/null || true)"
if [[ "${HEALTH}" == "healthy" ]]; then
  pass "PostgreSQL healthcheck is healthy"
else
  fail "PostgreSQL healthcheck is healthy (got ${HEALTH})"
fi

# ---------------------------------------------------------------
# PostgreSQL network isolation
# ---------------------------------------------------------------
PG_NET="$(docker inspect --format '{{json .NetworkSettings.Networks}}' "${PG}" 2>/dev/null)"
if grep -q 'poisoned-pipeline_internal_net' <<<"${PG_NET}"; then
  pass "PostgreSQL is on internal_net"
else
  fail "PostgreSQL is on internal_net"
fi
if grep -q 'poisoned-pipeline_player_net' <<<"${PG_NET}"; then
  fail "PostgreSQL is NOT on player_net"
else
  pass "PostgreSQL is NOT on player_net"
fi
if grep -q 'poisoned-pipeline_control_net' <<<"${PG_NET}"; then
  fail "PostgreSQL is NOT on control_net"
else
  pass "PostgreSQL is NOT on control_net"
fi

PG_IP="$(docker inspect --format '{{(index .NetworkSettings.Networks "poisoned-pipeline_internal_net").IPAddress}}' "${PG}" 2>/dev/null || true)"
if [[ "${PG_IP}" == "10.13.20.10" ]]; then
  pass "PostgreSQL internal_net address is 10.13.20.10"
else
  fail "PostgreSQL internal_net address is 10.13.20.10 (got ${PG_IP})"
fi

PORTS="$(docker port "${PG}" 2>/dev/null || true)"
if [[ -z "${PORTS}" ]]; then
  pass "PostgreSQL has no host-published ports"
else
  fail "PostgreSQL has no host-published ports"
fi

# ---------------------------------------------------------------
# Application container: SSH pivot endpoint
# ---------------------------------------------------------------
if docker compose exec -T application sh -lc \
     'ss -lntH | awk "{print \$4}" | grep -Eq "(:22|\.22)$"' >/dev/null 2>&1; then
  pass "sshd is listening on TCP 22 inside the application container"
else
  fail "sshd is listening on TCP 22 inside the application container"
fi

if docker compose exec -T application getent passwd pivot >/dev/null 2>&1; then
  pass "pivot account exists"
else
  fail "pivot account exists"
fi

PIVOT_FILE_META="$(docker compose exec -T application sh -lc \
  'stat -c "%U:%G %a" /root/s06_pivot.txt' 2>/dev/null | tr -d '\r\n')"
if [[ "${PIVOT_FILE_META}" == "root:root 600" ]]; then
  pass "/root/s06_pivot.txt is root:root 0600"
else
  fail "/root/s06_pivot.txt is root:root 0600 (got ${PIVOT_FILE_META})"
fi

if docker compose exec -T --user 10001:10001 application sh -lc \
     'test -r /root/s06_pivot.txt' 2>/dev/null; then
  fail "pipeline-app cannot read /root/s06_pivot.txt before escalation"
else
  pass "pipeline-app cannot read /root/s06_pivot.txt before escalation"
fi

# ---------------------------------------------------------------
# Database content
#
# These use `docker exec` (container name) not `docker compose exec`
# (service name). The service name is "postgres"; the container
# name is "pp-postgres". Mixing them up causes silent failures.
# ---------------------------------------------------------------
DB_NAME_VALUE="${POSTGRES_DB:-nexora_prod}"
DB_READER="${DB_READER_USER:-ctf_reader}"
DB_READER_PASS="${DB_READER_PASSWORD:-}"

ROW_COUNT="$(docker exec "${PG}" \
  psql -U postgres -d "${DB_NAME_VALUE}" -tA \
  -c "SELECT count(*) FROM ctf_final WHERE record_key='s06_final_record';" \
  2>/dev/null | tr -d '\r\n' || true)"

if [[ "${ROW_COUNT}" == "1" ]]; then
  pass "ctf_final row exists in nexora_prod"
else
  fail "ctf_final row exists in nexora_prod (count=${ROW_COUNT})"
fi

if [[ -n "${DB_READER_PASS}" ]]; then
  FLAG_VALUE="$(docker exec -e PGPASSWORD="${DB_READER_PASS}" "${PG}" \
    psql -h 127.0.0.1 -U "${DB_READER}" -d "${DB_NAME_VALUE}" -tA \
    -c "SELECT record_value FROM ctf_final WHERE record_key='s06_final_record';" \
    2>/dev/null | tr -d '\r\n' || true)"

  if [[ "${FLAG_VALUE}" == "${S06_FLAG}" ]]; then
    pass "ctf_reader can read the S06 flag via SELECT"
  else
    fail "ctf_reader can read the S06 flag via SELECT"
  fi

  if docker exec -e PGPASSWORD="${DB_READER_PASS}" "${PG}" \
       psql -h 127.0.0.1 -U "${DB_READER}" -d "${DB_NAME_VALUE}" \
       -c "INSERT INTO ctf_final (record_key, record_value) VALUES ('x','y');" \
       >/dev/null 2>&1; then
    fail "ctf_reader cannot INSERT"
  else
    pass "ctf_reader cannot INSERT"
  fi

  if docker exec -e PGPASSWORD="${DB_READER_PASS}" "${PG}" \
       psql -h 127.0.0.1 -U "${DB_READER}" -d "${DB_NAME_VALUE}" \
       -c "UPDATE ctf_final SET record_value='x' WHERE record_key='s06_final_record';" \
       >/dev/null 2>&1; then
    fail "ctf_reader cannot UPDATE"
  else
    pass "ctf_reader cannot UPDATE"
  fi

  if docker exec -e PGPASSWORD="${DB_READER_PASS}" "${PG}" \
       psql -h 127.0.0.1 -U "${DB_READER}" -d "${DB_NAME_VALUE}" \
       -c "DELETE FROM ctf_final WHERE record_key='s06_final_record';" \
       >/dev/null 2>&1; then
    fail "ctf_reader cannot DELETE"
  else
    pass "ctf_reader cannot DELETE"
  fi
else
  fail "DB_READER_PASSWORD is available for verification"
fi

# ---------------------------------------------------------------
# Direct route from player_net must fail
# ---------------------------------------------------------------
docker run --rm --network poisoned-pipeline_player_net alpine:3.20 \
  sh -c 'nc -z -w 3 10.13.20.10 5432' >/dev/null 2>&1 \
  && fail "player_net cannot reach PostgreSQL directly" \
  || pass "player_net cannot reach PostgreSQL directly"

# ---------------------------------------------------------------
# Application container networking
# ---------------------------------------------------------------
APP_IP_PLAYER="$(docker inspect --format '{{(index .NetworkSettings.Networks "poisoned-pipeline_player_net").IPAddress}}' "${APP}" 2>/dev/null || true)"
APP_IP_INTERNAL="$(docker inspect --format '{{(index .NetworkSettings.Networks "poisoned-pipeline_internal_net").IPAddress}}' "${APP}" 2>/dev/null || true)"

if [[ "${APP_IP_PLAYER}" == "10.13.10.30" ]]; then
  pass "Application player_net address is 10.13.10.30"
else
  fail "Application player_net address is 10.13.10.30 (got ${APP_IP_PLAYER})"
fi
if [[ "${APP_IP_INTERNAL}" == "10.13.20.1" ]]; then
  pass "Application internal_net address is 10.13.20.1"
else
  fail "Application internal_net address is 10.13.20.1 (got ${APP_IP_INTERNAL})"
fi

# ---------------------------------------------------------------
# Full intended pivot works: from a player_net container, tunnel and read
#
# The inner script is written to a temp file and mounted read-only
# so the secrets can be passed via `docker run -e ...` without
# shell escaping problems. Using a single-quoted `sh -c '...'`
# does NOT expand host variables inside the alpine container.
# ---------------------------------------------------------------
echo
echo "[*] Running end-to-end tunnel test from a player_net peer..."

if [[ -z "${S06_PIVOT_PASSWORD:-}" || -z "${DB_READER_PASSWORD:-}" ]]; then
  fail "pivot/reader secrets available for end-to-end test"
else
  E2E_SCRIPT="$(mktemp)"
  cat > "${E2E_SCRIPT}" <<'EOS'
#!/bin/sh
set -eu
apk add --no-cache openssh-client postgresql-client >/dev/null 2>&1

ASKPASS="$(mktemp)"
printf '#!/bin/sh\necho "%s"\n' "${PIVOT_PASS}" > "${ASKPASS}"
chmod 0700 "${ASKPASS}"

SSH_ASKPASS="${ASKPASS}" \
SSH_ASKPASS_REQUIRE=force \
setsid ssh \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o PreferredAuthentications=password \
  -o PubkeyAuthentication=no \
  -o NumberOfPasswordPrompts=1 \
  -o ExitOnForwardFailure=yes \
  -f -N -L 127.0.0.1:15432:10.13.20.10:5432 \
  -p "${PIVOT_PORT}" "${PIVOT_USER}@${PIVOT_HOST}"

rm -f "${ASKPASS}"
sleep 1

PGPASSWORD="${DB_PASS}" psql \
  -h 127.0.0.1 -p 15432 \
  -U "${DB_USER}" -d "${DB_NAME}" -tA \
  -c "SELECT record_value FROM ctf_final WHERE record_key='s06_final_record';"
EOS

  E2E_OUT="$(docker run --rm \
    --network poisoned-pipeline_player_net \
    -e PIVOT_USER="${S06_PIVOT_USER}" \
    -e PIVOT_PASS="${S06_PIVOT_PASSWORD}" \
    -e PIVOT_HOST="nexora-app" \
    -e PIVOT_PORT="22" \
    -e DB_USER="${DB_READER_USER}" \
    -e DB_PASS="${DB_READER_PASSWORD}" \
    -e DB_NAME="${POSTGRES_DB}" \
    -v "${E2E_SCRIPT}:/tmp/e2e.sh:ro" \
    alpine:3.20 sh /tmp/e2e.sh 2>/dev/null || true)"

  rm -f "${E2E_SCRIPT}"

  if grep -q "${S06_FLAG}" <<<"${E2E_OUT}"; then
    pass "End-to-end pivot from player_net recovers the S06 flag"
  else
    fail "End-to-end pivot from player_net recovers the S06 flag"
  fi
fi

echo
echo "=============================================================="
echo " RESULTS"
echo "=============================================================="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"
echo

if [[ "${FAIL}" -eq 0 ]]; then
  echo "PHASE 12 S06: PASSED"
  exit 0
else
  echo "PHASE 12 S06: FAILED"
  exit 1
fi