#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

MANIFEST="private/build-manifest.yml"

echo "=========================================="
echo " Operation Poisoned Pipeline"
echo " Build Manifest Generator"
echo "=========================================="
echo

# Helper: get image digest
get_digest() {
    local image="$1"
    docker image inspect "${image}" --format '{{index .RepoDigests 0}}' 2>/dev/null || echo "unknown"
}

# Helper: get image ID
get_image_id() {
    local image="$1"
    docker image inspect "${image}" --format '{{.Id}}' 2>/dev/null || echo "unknown"
}

# Helper: get file SHA256
get_file_sha() {
    local file="$1"
    if [[ -f "${file}" ]]; then
        sha256sum "${file}" | awk '{print $1}'
    else
        echo "missing"
    fi
}

# Gather values
HOST_OS="$(lsb_release -ds 2>/dev/null || cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"' || echo "unknown")"
HOST_ARCH="$(uname -m)"
DOCKER_VERSION="$(docker --version | awk '{print $3}' | tr -d ',')"
COMPOSE_VERSION="$(docker compose version --short 2>/dev/null || echo "unknown")"

NGINX_DIGEST="$(get_digest nginx:1.28.0-alpine)"
CTFD_DIGEST="$(get_digest ctfd/ctfd:3.8.7)"
MARIADB_DIGEST="$(get_digest mariadb:11.4.13)"
REDIS_DIGEST="$(get_digest redis:7.4.0-alpine)"
GITEA_DIGEST="$(get_digest gitea/gitea:1.27.0)"
JENKINS_BASE_DIGEST="$(get_digest jenkins/jenkins:lts-jdk21)"
POSTGRES_DIGEST="$(get_digest postgres:16.4-bookworm)"
PYTHON_BASE_DIGEST="$(get_digest python:3.9.25-slim-bookworm)"
KALI_BASE_DIGEST="$(get_digest kalilinux/kali-rolling:latest)"

APP_IMAGE_ID="$(get_image_id poisoned-pipeline/application:phase11)"
KALI_IMAGE_ID="$(get_image_id poisoned-pipeline/kali:phase13)"
JENKINS_IMAGE_ID="$(get_image_id poisoned-pipeline/jenkins:phase7)"

GIT_BUNDLE_SHA="$(get_file_sha private/s01/deployment-tools.bundle)"
S03_EVIDENCE_SHA="$(get_file_sha challenges/s03-ghost-dependency/dist/evidence-s03.zip)"
POSTGRES_SEED_SHA="$(get_file_sha postgres/init/01-init-nexora.sql)"

GIT_COMMIT="$(git rev-parse HEAD 2>/dev/null || echo "unknown")"
GIT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"

# Write manifest
cat > "${MANIFEST}" <<EOF
# ======================================================
# Operation Poisoned Pipeline
# Build Manifest
#
# This file records the exact versions, digests, and
# checksums used for the verified implementation.
# It lives under private/ and is not committed to the
# ordinary project repository.
# ======================================================

project:
  name: Operation Poisoned Pipeline
  description: Software supply chain CTF play box

host:
  os: "${HOST_OS}"
  architecture: "${HOST_ARCH}"
  docker_engine: "${DOCKER_VERSION}"
  docker_compose: "${COMPOSE_VERSION}"

implementation:
  git_branch: "${GIT_BRANCH}"
  git_commit: "${GIT_COMMIT}"
  generated_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

images:
  nginx:
    tag: "nginx:1.28.0-alpine"
    digest: "${NGINX_DIGEST}"
  ctfd:
    tag: "ctfd/ctfd:3.8.7"
    digest: "${CTFD_DIGEST}"
  mariadb:
    tag: "mariadb:11.4.13"
    digest: "${MARIADB_DIGEST}"
  redis:
    tag: "redis:7.4.0-alpine"
    digest: "${REDIS_DIGEST}"
  gitea:
    tag: "gitea/gitea:1.27.0"
    digest: "${GITEA_DIGEST}"
  jenkins_base:
    tag: "jenkins/jenkins:lts-jdk21"
    digest: "${JENKINS_BASE_DIGEST}"
  jenkins_local:
    tag: "poisoned-pipeline/jenkins:phase7"
    image_id: "${JENKINS_IMAGE_ID}"
  postgres:
    tag: "postgres:16.4-bookworm"
    digest: "${POSTGRES_DIGEST}"
  python_base:
    tag: "python:3.9.25-slim-bookworm"
    digest: "${PYTHON_BASE_DIGEST}"
  application:
    tag: "poisoned-pipeline/application:phase11"
    image_id: "${APP_IMAGE_ID}"
  kali_base:
    tag: "kalilinux/kali-rolling:latest"
    digest: "${KALI_BASE_DIGEST}"
  kali_local:
    tag: "poisoned-pipeline/kali:phase13"
    image_id: "${KALI_IMAGE_ID}"

baselines:
  git_bundle_sha256: "${GIT_BUNDLE_SHA}"
  s03_evidence_sha256: "${S03_EVIDENCE_SHA}"
  postgres_seed_sha256: "${POSTGRES_SEED_SHA}"

network:
  player_net:
    subnet: "10.13.10.0/24"
    gateway: "10.13.10.1"
  control_net:
    subnet: "docker-assigned"
    internal: true
  internal_net:
    subnet: "10.13.20.0/24"
    gateway: "10.13.20.254"
    internal: true

addresses:
  kali: "10.13.10.10"
  nginx_player: "10.13.10.20"
  application_player: "10.13.10.30"
  application_internal: "10.13.20.1"
  postgres_internal: "10.13.20.10"

flags:
  s01_format: "IE3132{PP_S01_<32 hex>}"
  s02_format: "IE3132{PP_S02_<32 hex>}"
  s03_format: "IE3132{PP_S03_<32 hex>}"
  s04_format: "IE3132{PP_S04_<32 hex>}"
  s05_format: "IE3132{PP_S05_<32 hex>}"
  s06_format: "IE3132{PP_S06_<32 hex>}"

scoring:
  s01: 100
  s02: 100
  s03: 150
  s04: 200
  s05: 200
  s06: 250
  total: 1000
EOF

chmod 600 "${MANIFEST}"

echo "[+] Build manifest written to ${MANIFEST}"
echo
echo "=========================================="
echo " BUILD MANIFEST COMPLETE"
echo "=========================================="
