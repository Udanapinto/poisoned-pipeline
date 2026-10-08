#!/usr/bin/env bash
# =============================================================
# Operation Poisoned Pipeline
# fast_reset.sh
#
# Instantly restores the environment to the golden state
# captured by create_golden_seed.sh.
#
# Workflow:
#   1. Verify golden-seed.tar.gz exists (failsafe)
#   2. Tear down the current environment
#   3. Delete and recreate all named volumes from the seed
#   4. Restore private/ and config paths from the seed
#   5. Bring the stack back up
# =============================================================

set -euo pipefail

# ─────────────────────────────────────────────────────────────
# Configuration (must match create_golden_seed.sh)
# ─────────────────────────────────────────────────────────────
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

PROJECT_NAME="${PROJECT_NAME:-poisoned-pipeline}"
SEED_FILE="${SEED_FILE:-${ROOT_DIR}/golden-seed.tar.gz}"
CONFIG_PATHS="${CONFIG_PATHS:-private nginx/certs challenges/s03-ghost-dependency/dist challenges/s03-ghost-dependency/keys}"
ALPINE_IMAGE="${ALPINE_IMAGE:-alpine:3.20}"

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
# FAILSAFE: verify the golden seed exists BEFORE anything destructive
# ─────────────────────────────────────────────────────────────
step "Failsafe checks"

if [[ ! -f "${SEED_FILE}" ]]; then
    err "Golden seed not found: ${SEED_FILE}"
    err "Run ./scripts/create_golden_seed.sh first — refusing to wipe data."
    exit 1
fi
pass "Golden seed found: ${SEED_FILE} ($(du -h "${SEED_FILE}" | cut -f1))"

# Verify it's a valid gzip archive
if ! tar tzf "${SEED_FILE}" >/dev/null 2>&1; then
    err "Golden seed is not a valid tar.gz archive — refusing to wipe data."
    exit 1
fi
pass "Golden seed is a valid tar.gz"

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

# Sanity: check the seed contains at least one volume snapshot.
# tar implementations differ on whether they prefix entries with "./",
# so we match on "volumes/" or on a specific volume filename.
if ! tar tzf "${SEED_FILE}" | grep -qE '(^|/)volumes/|mariadb_data\.tar\.gz'; then
    err "Golden seed does not contain any volume snapshots — refusing to wipe data."
    exit 1
fi
pass "Golden seed contains volume snapshots"

# Optional prompt
if [[ "${FORCE:-0}" != "1" && -t 0 ]]; then
    echo
    echo -e "${YELLOW}This will DELETE all current challenge state and restore the golden seed.${RESET}"
    read -r -p "Continue? [y/N] " REPLY
    if [[ ! "${REPLY}" =~ ^[Yy]$ ]]; then
        info "Aborted by user."
        exit 0
    fi
fi

# ─────────────────────────────────────────────────────────────
# Extract seed to temp dir
# ─────────────────────────────────────────────────────────────
step "Extracting golden seed"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

tar xzf "${SEED_FILE}" -C "${TMP_DIR}"
pass "Extracted to ${TMP_DIR}"

if [[ -f "${TMP_DIR}/metadata.txt" ]]; then
    echo
    head -n 12 "${TMP_DIR}/metadata.txt" | sed 's/^/    /'
    echo
fi

# ─────────────────────────────────────────────────────────────
# Stop and remove all containers
# ─────────────────────────────────────────────────────────────
step "Tearing down the current environment"

docker compose down --remove-orphans
pass "Containers, networks removed (volumes preserved)"

# ─────────────────────────────────────────────────────────────
# Remove current volumes
# ─────────────────────────────────────────────────────────────
step "Removing current named volumes"

for VOL in "${VOLUMES[@]}"; do
    if docker volume inspect "${VOL}" >/dev/null 2>&1; then
        info "Removing volume: ${VOL}"
        docker volume rm "${VOL}" >/dev/null
        pass "  → removed"
    else
        info "Volume not present — nothing to remove: ${VOL}"
    fi
done

# ─────────────────────────────────────────────────────────────
# Recreate volumes from the golden seed
# ─────────────────────────────────────────────────────────────
step "Recreating volumes from golden seed"

for VOL in "${VOLUMES[@]}"; do
    SNAPSHOT="${TMP_DIR}/volumes/${VOL}.tar.gz"
    if [[ ! -f "${SNAPSHOT}" ]]; then
        warn "No snapshot for ${VOL} — skipping"
        continue
    fi

    info "Restoring volume: ${VOL}"
    docker volume create "${VOL}" >/dev/null

    docker run --rm \
        -v "${VOL}:/target" \
        -v "${TMP_DIR}/volumes:/backup:ro" \
        "${ALPINE_IMAGE}" \
        tar xzf "/backup/${VOL}.tar.gz" -C /target \
        --numeric-owner

    pass "  → ${VOL} restored"
done

# ─────────────────────────────────────────────────────────────
# Restore project config directories
# ─────────────────────────────────────────────────────────────
step "Restoring project config and private material"

for REL_PATH in ${CONFIG_PATHS}; do
    SAFE_NAME="$(echo "${REL_PATH}" | tr '/' '_')"
    SNAPSHOT="${TMP_DIR}/config/${SAFE_NAME}.tar.gz"
    if [[ ! -f "${SNAPSHOT}" ]]; then
        warn "No snapshot for ${REL_PATH} — skipping"
        continue
    fi

    info "Restoring: ${REL_PATH}"

    # Remove old directory contents, then extract fresh
    rm -rf "${ROOT_DIR:?}/${REL_PATH}"
    tar xzf "${SNAPSHOT}" -C "${ROOT_DIR}" --numeric-owner

    pass "  → ${REL_PATH} restored"
done

# ─────────────────────────────────────────────────────────────
# Bring the stack back up
# ─────────────────────────────────────────────────────────────
step "Starting the environment"

docker compose up -d
pass "Stack started"

# ─────────────────────────────────────────────────────────────
# Wait for critical services
# ─────────────────────────────────────────────────────────────
step "Waiting for critical services to become healthy"

SERVICES=(
    "pp-mariadb:MariaDB"
    "pp-redis:Redis"
    "pp-ctfd:CTFd"
    "pp-jenkins:Jenkins"
    "pp-postgres:PostgreSQL"
    "pp-application:Application"
)

for ENTRY in "${SERVICES[@]}"; do
    CONTAINER="${ENTRY%%:*}"
    LABEL="${ENTRY##*:}"

    for i in $(seq 1 60); do
        STATUS="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${CONTAINER}" 2>/dev/null || echo missing)"
        if [[ "${STATUS}" == "healthy" || "${STATUS}" == "none" ]]; then
            pass "${LABEL} (${CONTAINER}) is ${STATUS}"
            break
        fi
        if [[ "${i}" -eq 60 ]]; then
            err "${LABEL} (${CONTAINER}) did not become healthy"
            docker compose logs --tail=30 "${CONTAINER}" || true
        fi
        sleep 2
    done
done

# ─────────────────────────────────────────────────────────────
# Verify reachability
# ─────────────────────────────────────────────────────────────
step "Verifying reachability"

# Give Nginx a moment to resolve the new backend containers
sleep 5

CODE_CTFD="$(curl -k -s -o /dev/null -w '%{http_code}' https://10.13.10.20/ 2>/dev/null || echo 000)"
CODE_GITEA="$(curl -k -s -o /dev/null -w '%{http_code}' https://10.13.10.20/git/ 2>/dev/null || echo 000)"
CODE_JENKINS="$(curl -k -s -o /dev/null -w '%{http_code}' https://10.13.10.20/jenkins/login 2>/dev/null || echo 000)"

[[ "${CODE_CTFD}" =~ ^(200|302)$ ]] && pass "CTFd reachable (${CODE_CTFD})" || warn "CTFd reachable? HTTP ${CODE_CTFD}"
[[ "${CODE_GITEA}" =~ ^(200|302)$ ]] && pass "Gitea reachable (${CODE_GITEA})" || warn "Gitea reachable? HTTP ${CODE_GITEA}"
[[ "${CODE_JENKINS}" =~ ^(200|302)$ ]] && pass "Jenkins reachable (${CODE_JENKINS})" || warn "Jenkins reachable? HTTP ${CODE_JENKINS}"

echo
echo -e "${BOLD}${GREEN}════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}${GREEN}  FAST RESET COMPLETE — GOLDEN STATE RESTORED${RESET}"
echo -e "${BOLD}${GREEN}════════════════════════════════════════════════${RESET}"
echo
echo "  Open: https://10.13.10.20/"
echo "  Login with your CTFd admin account."
echo
