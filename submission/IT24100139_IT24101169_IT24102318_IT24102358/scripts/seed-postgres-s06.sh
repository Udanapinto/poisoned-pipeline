#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S06_FILE="${ROOT_DIR}/private/s06/s06.env"

if [[ ! -f "${S06_FILE}" ]]; then
  echo "[ERROR] Missing ${S06_FILE}"
  echo "Run: ./scripts/generate-s06-secrets.sh"
  exit 1
fi

# shellcheck disable=SC1090
source "${S06_FILE}"

: "${POSTGRES_DB:?}"
: "${DB_READER_USER:?}"
: "${DB_READER_PASSWORD:?}"
: "${S06_FLAG:?}"

echo "[+] Waiting for PostgreSQL to become ready..."

for attempt in $(seq 1 60); do
  if docker compose exec -T postgres \
      pg_isready -U postgres -d "${POSTGRES_DB}" >/dev/null 2>&1; then
    echo "[+] PostgreSQL is ready."
    break
  fi
  sleep 2
  if [[ "${attempt}" -eq 60 ]]; then
    echo "[ERROR] PostgreSQL did not become ready."
    docker compose logs --tail=80 postgres
    exit 1
  fi
done

echo "[+] Applying read-only role password..."

docker compose exec -T postgres \
  psql -U postgres -d "${POSTGRES_DB}" \
  -v ON_ERROR_STOP=1 \
  -c "ALTER ROLE ${DB_READER_USER} WITH PASSWORD '${DB_READER_PASSWORD}';"

echo "[+] Upserting final S06 record..."

# psql variable substitution (:'flag') only works when psql reads SQL
# from stdin, not via -c. The INSERT ... ON CONFLICT DO UPDATE makes
# this idempotent, so it works whether the row exists or not.
docker compose exec -T postgres \
  psql -U postgres -d "${POSTGRES_DB}" \
  -v ON_ERROR_STOP=1 \
  -v flag="${S06_FLAG}" <<'SQL'
INSERT INTO ctf_final (record_key, record_value)
VALUES ('s06_final_record', :'flag')
ON CONFLICT (record_key) DO UPDATE
SET record_value = EXCLUDED.record_value;
SQL

echo "[+] PostgreSQL S06 seeding complete."