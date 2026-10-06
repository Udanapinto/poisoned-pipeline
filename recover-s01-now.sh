#!/usr/bin/env bash
set -euo pipefail

cd ~/Projects/poisoned-pipeline

printf '\n========== S01 RECOVERY START ==========\n\n'

for f in \
  .env \
  nginx/certs/ctf.crt \
  nginx/certs/ctf.key \
  private/s01/s01.env \
  private/s01/s01-signing-private.pem \
  private/s01/deployment-tools.bundle \
  private/s01/deployment-tools.bundle.sig \
  private/s01/baseline.env \
  gitea/seeds/s01-signing-public.pem
do
  if [[ ! -f "$f" ]]; then
    printf '[STOP] Missing required file: %s\n' "$f"
    exit 1
  fi
done

printf '[PASS] Required private/recovery files exist.\n'

docker compose config -q

printf '\n[1/8] Starting MariaDB and Redis...\n'
docker compose up -d mariadb redis

for i in $(seq 1 60); do
  DB_STATUS="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' pp-mariadb 2>/dev/null || true)"
  REDIS_STATUS="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' pp-redis 2>/dev/null || true)"

  if [[ "$DB_STATUS" == "healthy" && "$REDIS_STATUS" == "healthy" ]]; then
    break
  fi

  sleep 2
done

docker compose ps mariadb redis

printf '\n[2/8] Starting CTFd...\n'
docker compose up -d ctfd

for i in $(seq 1 60); do
  CTFD_STATUS="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' pp-ctfd 2>/dev/null || true)"

  if [[ "$CTFD_STATUS" == "healthy" ]]; then
    break
  fi

  sleep 2
done

docker compose ps ctfd

printf '\n[3/8] Starting Gitea and Nginx...\n'
docker compose up -d gitea
docker compose up -d nginx

sleep 5

docker compose ps

printf '\n[4/8] Testing CTFd...\n'
curl -k -I https://10.13.10.20/ || true

command -v xdg-open >/dev/null 2>&1 && \
  xdg-open https://10.13.10.20/ >/dev/null 2>&1 &

printf '\n============================================================\n'
printf 'COMPLETE CTFd SETUP IN THE BROWSER\n'
printf '============================================================\n'
printf 'Event Name: Operation Poisoned Pipeline\n'
printf 'User Mode: Users\n'
printf 'Create a NEW administrator account.\n'
printf 'Finish the setup and log in as administrator.\n'
printf '============================================================\n\n'

read -r -p "Press ENTER after CTFd setup is COMPLETELY finished: "

command -v xdg-open >/dev/null 2>&1 && \
  xdg-open https://10.13.10.20/admin/challenges >/dev/null 2>&1 &

# Phase-6 S01 challenge configuration. :chatgpt-content-reference{index="0"}
printf '\n============================================================\n'
printf 'CREATE CHALLENGE 01 IN CTFd\n'
printf '============================================================\n'
printf 'Type: Standard\n'
printf 'Name: The Git Leak\n'
printf 'Category: OSINT / Reconnaissance\n'
printf 'Value: 100\n'
printf 'Scoring Function: Static\n'
printf 'Logic: Require Any Flag\n'
printf 'Max Attempts: 0\n'
printf 'State: Hidden\n\n'

printf 'MESSAGE:\n\n'
printf 'Nexora Technologies published part of its deployment\n'
printf 'tooling in a simulated repository.\n\n'
printf 'A developer believed that removing sensitive information\n'
printf 'from the latest revision was enough to eliminate it.\n\n'
printf 'Investigate the repository history and identify the\n'
printf 'accidental disclosure.\n\n'
printf 'Repository:\n'
printf 'https://10.13.10.20/git/nexora/deployment-tools\n\n'
printf 'Recover the S01 token and preserve any CI/CD information\n'
printf 'that may be useful later.\n\n'

printf 'HINT 1\n'
printf 'Title: Hint 1\n'
printf 'Cost: 5\n'
printf 'Hint: The latest tree may not contain the full story.\n\n'

printf 'HINT 2\n'
printf 'Title: Hint 2\n'
printf 'Cost: 10\n'
printf 'Hint: Inspect earlier commits and file history.\n\n'

printf 'HINT 3\n'
printf 'Title: Hint 3\n'
printf 'Cost: 15\n'
printf 'Hint: Compare versions of the deployment configuration.\n'
printf '============================================================\n\n'

source private/s01/s01.env

if command -v xclip >/dev/null 2>&1; then
  printf '%s' "$S01_FLAG" | xclip -selection clipboard
  printf '[PASS] S01 flag copied to clipboard.\n'
  printf 'Paste it into: Flags -> New Flag -> Static\n'
elif command -v wl-copy >/dev/null 2>&1; then
  printf '%s' "$S01_FLAG" | wl-copy
  printf '[PASS] S01 flag copied to clipboard.\n'
  printf 'Paste it into: Flags -> New Flag -> Static\n'
else
  command -v code >/dev/null 2>&1 && \
    code private/s01/s01.env >/dev/null 2>&1 &
  printf '[ACTION] s01.env opened in VS Code.\n'
  printf 'Copy ONLY the value after S01_FLAG= into the CTFd Static Flag field.\n'
fi

read -r -p "Press ENTER after The Git Leak + Static Flag + 3 separate Hints are saved and State is HIDDEN: "

printf '\n[5/8] Restoring the S01 Gitea repository...\n'

# This is the Phase-6 designed S01 reset/reseed procedure. :chatgpt-content-reference{index="1"}
./scripts/reset-s01.sh

printf '\n[6/8] Running automatic S01 verification...\n'
./tests/stages/verify-phase6-s01.sh

printf '\n[7/8] Opening Gitea repository...\n'
command -v xdg-open >/dev/null 2>&1 && \
  xdg-open https://10.13.10.20/git/nexora/deployment-tools >/dev/null 2>&1 &

printf '\nRepository must open successfully:\n'
printf 'https://10.13.10.20/git/nexora/deployment-tools\n\n'

read -r -p "Press ENTER after you confirm the Gitea repository opens correctly: "

printf '\n[8/8] Make S01 visible in CTFd...\n'
command -v xdg-open >/dev/null 2>&1 && \
  xdg-open https://10.13.10.20/admin/challenges >/dev/null 2>&1 &

printf '\n============================================================\n'
printf 'OPEN: The Git Leak\n'
printf 'CHANGE: State -> Visible\n'
printf 'SAVE / UPDATE THE CHALLENGE\n'
printf '============================================================\n\n'

read -r -p "Press ENTER after State is changed to VISIBLE and saved: "

command -v xdg-open >/dev/null 2>&1 && \
  xdg-open https://10.13.10.20/challenges >/dev/null 2>&1 &

mkdir -p private/backups

docker compose exec -T mariadb sh -lc \
  'mariadb-dump -uroot -p"$MARIADB_ROOT_PASSWORD" "$MARIADB_DATABASE"' \
  > private/backups/ctfd-s01.sql

chmod 600 private/backups/ctfd-s01.sql

printf '\n========== FINAL CHECK ==========\n'

docker compose ps

./tests/stages/verify-phase6-s01.sh

printf '\nCTFd participant page:\n'
printf 'https://10.13.10.20/challenges\n\n'

printf 'Gitea S01 repository:\n'
printf 'https://10.13.10.20/git/nexora/deployment-tools\n\n'

printf 'CTFd database backup created:\n'
printf 'private/backups/ctfd-s01.sql\n\n'

# Phase-6 final target: S01 challenge, flag, hints, Gitea history and validation. :chatgpt-content-reference{index="2"}
printf '========== S01 RECOVERY COMPLETE ==========\n'
