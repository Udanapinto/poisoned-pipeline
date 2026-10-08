#!/usr/bin/env bash
# =============================================================
# Operation Poisoned Pipeline
# create_golden_seed.sh
#
# Snapshots the current fully-provisioned CTF state (docker
# named volumes + private config + TLS certs) into a single
# compressed archive: golden-seed.tar.gz
#
# Run this ONCE after you have:
#   1. Provisioned the entire environment
#   2. Configured CTFd (challenges, hints, flags, admin)
#   3. Verified all six stages
# =============================================================

set -euo pipefail

# ─────────────────────────────────────────────────────────────
# Configuration (override with env vars if needed)
# ─────────────────────────────────────────────────────────────
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

PROJECT_NAME="${PROJECT_NAME:-poisoned-pipeline}"
SEED_FILE="${SEED_FILE:-${ROOT_DIR}/golden-seed.tar.gz}"
CONFIG_PATHS="${CONFIG_PATHS:-private nginx/certs challenges/s03-ghost-dependency/dist challenges/s03-ghost-dependency/keys}"
ALPINE_IMAGE="${ALPINE_IMAGE:-alpine:3.20}"

# Named volumes created by compose.yml (Docker prefixes with project name)
VOLUMES=(
    "${PROJECT_NAME}_mariadb_data"
    "${PROJECT_NAME}_redis_data"
    "${PROJECT_NAME}_ctfd_uploads"
    "${PROJECT_NAME}_ctfd_logs"
    "${PROJECT_NAME}_gitea_data"
    "${PROJECT_NAME}_jenkins_data"
    "${PROJECT_NAME}_postgres_data"
)

# ─────────────────────────────────────────────────────────────
# Colors
# ─────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

info() { echo -e "${BLUE}[INFO]${RESET} $*"; }
pass() { echo -e "${GREEN}[PASS]${RESET} $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $*"; }
err()  { echo -e "${RED}[FAIL]${RESET} $*"; }
step() { echo -e "\n${BOLD}${BLUE}▶ $*${RESET}"; }

# ─────────────────────────────────────────────────────────────
# Preflight checks
# ─────────────────────────────────────────────────────────────
step "Preflight checks"

if ! command -v docker >/dev/null 2>&1; then
    err "docker is not installed or not in PATH"
    exit 1
fi
pass "docker found"

if [[ ! -f "${ROOT_DIR}/compose.yml" ]]; then
    err "compose.yml not found at ${ROOT_DIR}/compose.yml"
    exit 1
fi
pass "compose.yml found"

RUNNING="$(docker compose ps --status running --quiet 2>/dev/null | wc -l)"
if [[ "${RUNNING}" -eq 0 ]]; then
    warn "No running containers detected — did you forget 'docker compose up -d'?"
fi

# Ensure volume directory at project root is writable
if [[ ! -w "${ROOT_DIR}" ]]; then
    err "Project root is not writable: ${ROOT_DIR}"
    exit 1
fi
pass "Project root writable"

# ─────────────────────────────────────────────────────────────
# Stop the stack gracefully
# ─────────────────────────────────────────────────────────────
step "Stopping containers gracefully"

docker compose stop
pass "All containers stopped"

# ─────────────────────────────────────────────────────────────
# Temporary working directory
# ─────────────────────────────────────────────────────────────
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${TMP_DIR}/volumes" "${TMP_DIR}/config"

# ─────────────────────────────────────────────────────────────
# Snapshot each Docker named volume
# ─────────────────────────────────────────────────────────────
step "Snapshotting Docker named volumes"

for VOL in "${VOLUMES[@]}"; do
    # Does this volume exist?
    if ! docker volume inspect "${VOL}" >/dev/null 2>&1; then
        warn "Volume not found — skipping: ${VOL}"
        continue
    fi

    info "Backing up: ${VOL}"
    docker run --rm \
        -v "${VOL}:/source:ro" \
        -v "${TMP_DIR}/volumes:/backup" \
        "${ALPINE_IMAGE}" \
        tar czf "/backup/${VOL}.tar.gz" -C /source . \
        >/dev/null
    pass "  → ${VOL}.tar.gz ($(du -h "${TMP_DIR}/volumes/${VOL}.tar.gz" | cut -f1))"
done

# ─────────────────────────────────────────────────────────────
# Snapshot project config directories
# ─────────────────────────────────────────────────────────────
step "Snapshotting project config and private material"

for REL_PATH in ${CONFIG_PATHS}; do
    ABS_PATH="${ROOT_DIR}/${REL_PATH}"
    if [[ ! -d "${ABS_PATH}" ]]; then
        warn "Config path missing — skipping: ${REL_PATH}"
        continue
    fi
    SAFE_NAME="$(echo "${REL_PATH}" | tr '/' '_')"
    info "Backing up: ${REL_PATH}"
    tar czf "${TMP_DIR}/config/${SAFE_NAME}.tar.gz" -C "${ROOT_DIR}" "${REL_PATH}"
    pass "  → ${SAFE_NAME}.tar.gz"
done

# ─────────────────────────────────────────────────────────────
# Write metadata about this golden seed
# ─────────────────────────────────────────────────────────────
step "Writing golden seed metadata"

GIT_COMMIT="$(git -C "${ROOT_DIR}" rev-parse HEAD 2>/dev/null || echo "unknown")"
GIT_BRANCH="$(git -C "${ROOT_DIR}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"

cat > "${TMP_DIR}/metadata.txt" <<EOF
Operation Poisoned Pipeline — Golden Seed
==========================================
Generated:     $(date -u +%Y-%m-%dT%H:%M:%SZ)
Host OS:       $(lsb_release -ds 2>/dev/null || cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')
Docker:        $(docker --version)
Compose:       $(docker compose version --short 2>/dev/null || echo unknown)
Project name:  ${PROJECT_NAME}
Git commit:    ${GIT_COMMIT}
Git branch:    ${GIT_BRANCH}

Volumes included:
$(printf '  - %s\n' "${VOLUMES[@]}")

Config paths included:
$(printf '  - %s\n' ${CONFIG_PATHS})

Restore with:
    ./scripts/fast_reset.sh
EOF

pass "Metadata written"

# ─────────────────────────────────────────────────────────────
# Create the golden seed archive
# ─────────────────────────────────────────────────────────────
step "Creating golden-seed.tar.gz"

# Remove old seed if present, but keep a .bak for safety
if [[ -f "${SEED_FILE}" ]]; then
    warn "Existing golden seed found — rotating to ${SEED_FILE}.bak"
    mv "${SEED_FILE}" "${SEED_FILE}.bak"
fi

tar czf "${SEED_FILE}" -C "${TMP_DIR}" .

pass "Golden seed created: ${SEED_FILE} ($(du -h "${SEED_FILE}" | cut -f1))"

# ─────────────────────────────────────────────────────────────
# Restart the stack
# ─────────────────────────────────────────────────────────────
step "Restarting the stack"

docker compose up -d
pass "Stack is back up"

# Wait for critical services to become healthy
info "Waiting for MariaDB and CTFd to become healthy..."
for i in $(seq 1 60); do
    MARIA="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' pp-mariadb 2>/dev/null || echo starting)"
    CTFD="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' pp-ctfd 2>/dev/null || echo starting)"
    if [[ "${MARIA}" == "healthy" && "${CTFD}" == "healthy" ]]; then
        pass "MariaDB and CTFd are healthy"
        break
    fi
    sleep 2
done

echo
echo -e "${BOLD}${GREEN}════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}${GREEN}  GOLDEN SEED CREATED SUCCESSFULLY${RESET}"
echo -e "${BOLD}${GREEN}════════════════════════════════════════════════${RESET}"
echo
echo "  Seed file:    ${SEED_FILE}"
echo "  Size:         $(du -h "${SEED_FILE}" | cut -f1)"
echo "  Volumes:      ${#VOLUMES[@]}"
echo "  Config paths: $(echo ${CONFIG_PATHS} | wc -w)"
echo
echo "  To restore later, run:"
echo "      ./scripts/fast_reset.sh"
echo
