#!/usr/bin/env bash
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

BASE_URL="https://10.13.10.20"

PASS=0
FAIL=0

pass() { echo "[PASS] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

echo "======================================================"
echo " Operation Poisoned Pipeline"
echo " Phase 14 - CTFd Integration Verification"
echo "======================================================"
echo

# --- CTFd reachable through Nginx ---
CODE="$(curl -kfsS -o /dev/null -w '%{http_code}' "${BASE_URL}/" 2>/dev/null || true)"
if [[ "${CODE}" =~ ^(200|301|302|303|307|308)$ ]]; then
    pass "CTFd is reachable through Nginx (${CODE})"
else
    fail "CTFd is reachable through Nginx (got ${CODE})"
fi

# --- CTFd container healthy ---
HEALTH="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}unknown{{end}}' pp-ctfd 2>/dev/null || true)"
if [[ "${HEALTH}" == "healthy" ]]; then
    pass "CTFd container is healthy"
else
    fail "CTFd container is healthy (got ${HEALTH})"
fi

# --- MariaDB and Redis isolated ---
for SVC in pp-mariadb pp-redis; do
    NETS="$(docker inspect --format '{{json .NetworkSettings.Networks}}' "${SVC}" 2>/dev/null || true)"
    if grep -q 'poisoned-pipeline_control_net' <<<"${NETS}"; then
        if grep -q 'poisoned-pipeline_player_net' <<<"${NETS}"; then
            fail "${SVC} is NOT on player_net"
        else
            pass "${SVC} is on control_net only"
        fi
    else
        fail "${SVC} is on control_net"
    fi
done

# --- Nginx spans player_net and control_net ---
NGINX_NETS="$(docker inspect --format '{{json .NetworkSettings.Networks}}' pp-nginx 2>/dev/null || true)"
if grep -q 'poisoned-pipeline_player_net' <<<"${NGINX_NETS}" && \
   grep -q 'poisoned-pipeline_control_net' <<<"${NGINX_NETS}"; then
    pass "Nginx spans player_net and control_net"
else
    fail "Nginx spans player_net and control_net"
fi

# --- Backend ports not published ---
for SVC in pp-mariadb pp-redis pp-ctfd pp-gitea pp-jenkins pp-postgres; do
    PORTS="$(docker port "${SVC}" 2>/dev/null || true)"
    if [[ -z "${PORTS}" ]]; then
        pass "${SVC} has no host-published ports"
    else
        fail "${SVC} has no host-published ports"
    fi
done

# --- Nginx publishes only 443 ---
NGINX_PORTS="$(docker port pp-nginx 2>/dev/null || true)"
if grep -q '443' <<<"${NGINX_PORTS}"; then
    pass "Nginx publishes TCP 443"
else
    fail "Nginx publishes TCP 443"
fi

if grep -qE '(80|3000|5000|8000|8080|3306|6379|5432):' <<<"${NGINX_PORTS}"; then
    fail "Nginx does not publish backend ports"
else
    pass "Nginx does not publish backend ports"
fi

# --- CTFd backend connectivity ---
if docker exec pp-ctfd python -c '
import socket
socket.create_connection(("mariadb", 3306), 3).close()
socket.create_connection(("redis", 6379), 3).close()
' >/dev/null 2>&1; then
    pass "CTFd can reach MariaDB and Redis"
else
    fail "CTFd can reach MariaDB and Redis"
fi

# --- CTFd external egress blocked ---
if docker exec pp-ctfd python -c '
import socket
try:
    socket.create_connection(("1.1.1.1", 443), 3).close()
    raise SystemExit(1)
except Exception:
    raise SystemExit(0)
' >/dev/null 2>&1; then
    pass "CTFd external egress is blocked"
else
    fail "CTFd external egress is blocked"
fi

echo
echo "======================================================"
echo " RESULTS"
echo "======================================================"
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"
echo

if [[ "${FAIL}" -eq 0 ]]; then
    echo "PHASE 14 CTFD: PASSED"
    exit 0
else
    echo "PHASE 14 CTFD: FAILED"
    exit 1
fi

