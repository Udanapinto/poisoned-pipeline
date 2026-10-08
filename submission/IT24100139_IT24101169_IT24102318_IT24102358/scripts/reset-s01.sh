#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"


echo "=================================================="
echo " Operation Poisoned Pipeline"
echo " S01 Reset"
echo "=================================================="
echo


# --------------------------------------------------
# Stop/remove Gitea container
# --------------------------------------------------

echo "[+] Stopping Gitea..."

docker compose stop gitea >/dev/null 2>&1 || true


docker compose rm \
    -f \
    gitea \
    >/dev/null 2>&1 || true


# --------------------------------------------------
# Locate Gitea volume
# --------------------------------------------------

VOLUME="$(docker volume ls \
    -q \
    --filter label=com.docker.compose.project=poisoned-pipeline \
    --filter label=com.docker.compose.volume=gitea_data \
    | head -n 1)"


if [[ -n "$VOLUME" ]]; then

    echo "[+] Removing Gitea challenge volume: $VOLUME"

    docker volume rm "$VOLUME" >/dev/null

fi


# --------------------------------------------------
# Recreate Gitea
# --------------------------------------------------

echo "[+] Recreating Gitea..."

docker compose up -d gitea


# --------------------------------------------------
# Wait for Gitea HTTP API to be reachable through
# Nginx. The container itself starts within a few
# seconds, but the HTTP server needs more time.
# --------------------------------------------------

echo "[+] Waiting for Gitea HTTP API to become ready..."

for attempt in $(seq 1 60); do

    CODE="$(curl -k -s -o /dev/null -w '%{http_code}' \
        "https://10.13.10.20/git/api/v1/version" 2>/dev/null || true)"

    if [[ "${CODE}" == "200" ]]; then
        echo "    Gitea is ready (HTTP ${CODE})."
        break
    fi

    if [[ "${attempt}" -eq 60 ]]; then
        echo "[ERROR] Gitea did not become ready in time."
        docker compose logs --tail=50 gitea
        exit 1
    fi

    sleep 2

done


# --------------------------------------------------
# Nginx must refresh Docker DNS for recreated Gitea
# --------------------------------------------------

echo "[+] Restarting Nginx to refresh backend DNS..."

docker compose restart nginx >/dev/null


# Wait for nginx to serve Gitea

for attempt in $(seq 1 30); do

    CODE="$(curl -k -s -o /dev/null -w '%{http_code}' \
        "https://10.13.10.20/git/" 2>/dev/null || true)"

    if [[ "${CODE}" =~ ^(200|301|302|401)$ ]]; then
        echo "    Nginx is proxying Gitea (HTTP ${CODE})."
        break
    fi

    if [[ "${attempt}" -eq 30 ]]; then
        echo "[ERROR] Nginx is not proxying Gitea in time."
        docker compose logs --tail=50 nginx
        exit 1
    fi

    sleep 2

done


# --------------------------------------------------
# Load private config
# --------------------------------------------------

source "$ROOT_DIR/private/s01/s01.env"


# --------------------------------------------------
# Recreate Gitea admin
# --------------------------------------------------

echo "[+] Recreating Gitea admin..."

docker compose exec -T \
  --user git \
  gitea \
  gitea admin user create \
  --config /data/gitea/conf/app.ini \
  --username "$GITEA_ADMIN_USER" \
  --password "$GITEA_ADMIN_PASSWORD" \
  --email "$GITEA_ADMIN_EMAIL" \
  --admin \
  --must-change-password=false \
  || echo "    (admin user may already exist, continuing)"


# --------------------------------------------------
# Restore signed challenge seed
# --------------------------------------------------

"$ROOT_DIR/scripts/seed-gitea-s01.sh"


echo
echo "[+] Running S01 validation..."

"$ROOT_DIR/tests/stages/verify-phase6-s01.sh"


echo
echo "=================================================="
echo " S01 RESET COMPLETE"
echo "=================================================="
