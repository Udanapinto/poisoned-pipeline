ARG PYTHON_BASE_IMAGE=python:3.9.25-slim-bookworm

FROM ${PYTHON_BASE_IMAGE}

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# ==========================================================
# Base challenge utilities
#
# OpenSSH + sudo are installed now because this SAME image
# becomes the foundation for S05 and S06.
#
# Neither SSH nor passwordless sudo is enabled in Phase 9.
# ==========================================================
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        jq \
        gcc \
        sudo \
        openssh-server \
        iproute2 \
        procps \
        netcat-openbsd \
        acl \
        binutils \
        gosu \
    && rm -rf /var/lib/apt/lists/*

# ==========================================================
# Low-privileged application account
# ==========================================================
RUN groupadd \
        --gid 10001 \
        pipeline-app \
    && useradd \
        --uid 10001 \
        --gid 10001 \
        --create-home \
        --shell /bin/bash \
        pipeline-app \
    && passwd -l pipeline-app

# ==========================================================
# Runtime directories
# ==========================================================
RUN mkdir -p \
        /opt/nexora/app \
        /run/sshd \
    && chown -R root:root /opt/nexora \
    && chmod 0755 \
        /opt/nexora \
        /opt/nexora/app \
        /run/sshd

# ==========================================================
# Python dependencies
# ==========================================================
WORKDIR /opt/nexora

COPY requirements.txt /opt/nexora/requirements.txt

RUN python -m pip install \
        --no-cache-dir \
        -r /opt/nexora/requirements.txt

# ==========================================================
# Application source
# ==========================================================
COPY app/ /opt/nexora/app/

# ==========================================================
# S04 - Poisoned Runtime materials
# ==========================================================
# The vulnerable diagnostics helper and the S05 handoff clue
# are part of the intentionally vulnerable release build.
COPY bin/ /opt/nexora/bin/
COPY config/ /opt/nexora/config/

# The S04 flag file is generated privately by
# scripts/generate-s04-secrets.sh and staged at
# application/.s04-private/ before build. It is copied into the
# container as pipeline-app-readable only.
COPY .s04-private/ /opt/nexora/private/

RUN chmod 0755 /opt/nexora/bin/verify-component \
    && chown -R root:root /opt/nexora/bin /opt/nexora/config \
    && chmod 0755 /opt/nexora/config \
    && chmod 0644 /opt/nexora/config/deployment.conf \
    && chown -R pipeline-app:pipeline-app /opt/nexora/private \
    && chmod 0700 /opt/nexora/private \
    && find /opt/nexora/private -type f -exec chmod 0600 {} \;


COPY scripts/entrypoint.sh \
    /usr/local/bin/pp-entrypoint

# Keep application source root-owned and non-writable
# by pipeline-app during Phase 9.
RUN chmod 0755 /usr/local/bin/pp-entrypoint \
    && chown -R root:root /opt/nexora \
    && find /opt/nexora \
         -type d \
         -not -path '/opt/nexora/private*' \
         -exec chmod 0755 {} \; \
    && find /opt/nexora \
         -type f \
         -not -path '/opt/nexora/private/*' \
         -not -path '/opt/nexora/bin/*' \
         -exec chmod 0644 {} \; \
    && chown -R pipeline-app:pipeline-app /opt/nexora/private \
    && chmod 0700 /opt/nexora/private \
    && find /opt/nexora/private -type f -exec chmod 0600 {} \;

EXPOSE 5000

ENTRYPOINT ["/usr/local/bin/pp-entrypoint"]