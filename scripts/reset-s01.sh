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


echo "[+] Waiting for Gitea startup..."


for attempt in $(seq 1 30); do

    if docker compose logs gitea 2>&1 \
        | grep -qi "Listen"
    then
        break
    fi

    sleep 2

done


# --------------------------------------------------
# Nginx must refresh Docker DNS for recreated Gitea
# --------------------------------------------------

echo "[+] Restarting Nginx..."

docker compose restart nginx >/dev/null


sleep 5


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
  --must-change-password=false


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