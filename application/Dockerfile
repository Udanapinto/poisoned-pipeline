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

COPY scripts/entrypoint.sh \
    /usr/local/bin/pp-entrypoint

# Keep application source root-owned and non-writable
# by pipeline-app during Phase 9.
RUN chmod 0755 /usr/local/bin/pp-entrypoint \
    && chown -R root:root /opt/nexora \
    && find /opt/nexora \
        -type d \
        -exec chmod 0755 {} \; \
    && find /opt/nexora \
        -type f \
        -exec chmod 0644 {} \;

EXPOSE 5000

ENTRYPOINT ["/usr/local/bin/pp-entrypoint"]