#!/usr/bin/env bash
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

MANIFEST="private/build-manifest.yml"

PASS=0
FAIL=0

pass() { echo "[PASS] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

echo "======================================================"
echo " Operation Poisoned Pipeline"
echo " Reproducibility Verification"
echo "======================================================"
echo

if [[ ! -f "${MANIFEST}" ]]; then
    fail "Build manifest exists"
    echo "Run: ./scripts/generate-build-manifest.sh"
    exit 1
fi
pass "Build manifest exists"

# --- Verify recorded image digests match current images ---
check_digest() {
    local name="$1"
    local tag="$2"
    local recorded="$3"

    local current
    current="$(docker image inspect "${tag}" --format '{{index .RepoDigests 0}}' 2>/dev/null || echo "missing")"

    if [[ "${current}" == "${recorded}" ]]; then
        pass "${name} digest matches manifest"
    else
        fail "${name} digest matches manifest (recorded=${recorded}, current=${current})"
    fi
}

# Extract recorded digests from manifest
NGINX_RECORDED="$(grep -A2 '  nginx:' "${MANIFEST}" | grep 'digest:' | awk '{print $2}' | tr -d '"')"
CTFD_RECORDED="$(grep -A2 '  ctfd:' "${MANIFEST}" | grep 'digest:' | awk '{print $2}' | tr -d '"')"
MARIADB_RECORDED="$(grep -A2 '  mariadb:' "${MANIFEST}" | grep 'digest:' | awk '{print $2}' | tr -d '"')"
REDIS_RECORDED="$(grep -A2 '  redis:' "${MANIFEST}" | grep 'digest:' | awk '{print $2}' | tr -d '"')"
GITEA_RECORDED="$(grep -A2 '  gitea:' "${MANIFEST}" | grep 'digest:' | awk '{print $2}' | tr -d '"')"
POSTGRES_RECORDED="$(grep -A2 '  postgres:' "${MANIFEST}" | grep 'digest:' | awk '{print $2}' | tr -d '"')"

check_digest "nginx" "nginx:1.28.0-alpine" "${NGINX_RECORDED}"
check_digest "ctfd" "ctfd/ctfd:3.8.7" "${CTFD_RECORDED}"
check_digest "mariadb" "mariadb:11.4.13" "${MARIADB_RECORDED}"
check_digest "redis" "redis:7.4.0-alpine" "${REDIS_RECORDED}"
check_digest "gitea" "gitea/gitea:1.27.0" "${GITEA_RECORDED}"
check_digest "postgres" "postgres:16.4-bookworm" "${POSTGRES_RECORDED}"

# --- Verify seed checksums ---
check_file_sha() {
    local name="$1"
    local file="$2"
    local recorded="$3"

    if [[ ! -f "${file}" ]]; then
        fail "${name} file exists"
        return
    fi

    local current
    current="$(sha256sum "${file}" | awk '{print $1}')"

    if [[ "${current}" == "${recorded}" ]]; then
        pass "${name} checksum matches manifest"
    else
        fail "${name} checksum matches manifest (recorded=${recorded}, current=${current})"
    fi
}

GIT_BUNDLE_RECORDED="$(grep 'git_bundle_sha256:' "${MANIFEST}" | awk '{print $2}' | tr -d '"')"
S03_EVIDENCE_RECORDED="$(grep 's03_evidence_sha256:' "${MANIFEST}" | awk '{print $2}' | tr -d '"')"
POSTGRES_SEED_RECORDED="$(grep 'postgres_seed_sha256:' "${MANIFEST}" | awk '{print $2}' | tr -d '"')"

check_file_sha "Git bundle" "private/s01/deployment-tools.bundle" "${GIT_BUNDLE_RECORDED}"
check_file_sha "S03 evidence" "challenges/s03-ghost-dependency/dist/evidence-s03.zip" "${S03_EVIDENCE_RECORDED}"
check_file_sha "PostgreSQL seed" "postgres/init/01-init-nexora.sql" "${POSTGRES_SEED_RECORDED}"

# --- Verify all services reach healthy state ---
for SVC in pp-mariadb pp-redis pp-ctfd pp-postgres pp-application; do
    HEALTH="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${SVC}" 2>/dev/null || true)"
    if [[ "${HEALTH}" == "healthy" ]]; then
        pass "${SVC} is healthy"
    else
        fail "${SVC} is healthy (got ${HEALTH})"
    fi
done

echo
echo "======================================================"
echo " RESULTS"
echo "======================================================"
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"
echo

if [[ "${FAIL}" -eq 0 ]]; then
    echo "REPRODUCIBILITY: PASSED"
    exit 0
else
    echo "REPRODUCIBILITY: FAILED"
    exit 1
fi
