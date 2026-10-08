#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "=================================================="
echo " Operation Poisoned Pipeline"
echo " S02 Jenkins Reset"
echo "=================================================="
echo

echo "[+] Stopping Jenkins..."

docker compose stop jenkins >/dev/null 2>&1 || true

docker compose rm \
-f \
jenkins \
>/dev/null 2>&1 || true

VOLUME="$(
docker volume ls \
-q \
--filter label=com.docker.compose.project=poisoned-pipeline \
--filter label=com.docker.compose.volume=jenkins_data \
| head -n 1
)"

if [[ -n "$VOLUME" ]]; then

    echo "[+] Removing Jenkins challenge volume."

    docker volume rm \
    "$VOLUME" \
    >/dev/null

fi

echo "[+] Recreating Jenkins..."

docker compose up -d jenkins

echo "[+] Waiting for Jenkins health..."

for attempt in $(seq 1 60); do

    STATUS="$(
        docker inspect \
        --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}starting{{end}}' \
        pp-jenkins \
        2>/dev/null \
        || true
    )"

    if [[ "$STATUS" == "healthy" ]]; then
        break
    fi

    sleep 2
done

STATUS="$(
docker inspect \
--format '{{if .State.Health}}{{.State.Health.Status}}{{else}}unknown{{end}}' \
pp-jenkins
)"

if [[ "$STATUS" != "healthy" ]]; then

    echo "[ERROR] Jenkins did not become healthy."

    docker compose logs \
    --tail=100 \
    jenkins

    exit 1
fi

# Docker DNS address may have changed after container recreation.
echo "[+] Restarting Nginx..."

docker compose restart nginx >/dev/null

sleep 5

echo "[+] Re-seeding S02..."

"$ROOT_DIR/scripts/seed-jenkins-s02.sh"

echo
echo "[+] Validating S02..."

"$ROOT_DIR/tests/stages/verify-phase7-s02.sh"

echo
echo "=================================================="
echo " S02 RESET COMPLETE"
echo "=================================================="