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
# application/.s04-private/ before build.
COPY .s04-private/ /opt/nexora/private/

RUN chmod 0755 /opt/nexora/bin/verify-component \
    && chmod 0755 /opt/nexora/bin/deploy-verify \
    && chown -R root:root /opt/nexora/bin /opt/nexora/config \
    && chmod 0755 /opt/nexora/config \
    && chmod 0644 /opt/nexora/config/deployment.conf \
    && chown -R pipeline-app:pipeline-app /opt/nexora/private \
    && chmod 0700 /opt/nexora/private \
    && find /opt/nexora/private -type f -exec chmod 0600 {} \;

# ==========================================================
# S05 - Broken Trust materials
# ==========================================================
#
# The privileged deploy-verify utility, its sudoers policy,
# and the group-writable validation hook.
#
# The hook file must be group-writable AND executable:
#   owner root            : rwx   (0755 semantics for owner)
#   group pipeline-app    : rwx   (w -> exploit, x -> deploy-verify accepts it)
#   others                : r-x
# Mode 0775.
#
COPY sudoers/pp-pipeline-app /etc/sudoers.d/pp-pipeline-app
COPY hooks/ /opt/nexora/hooks/

# S05 private material (staged by scripts/build-application.sh).
# Contains the S05 flag and the S06 pivot credential.
COPY .s05-private/ /root/.s05-stage/

RUN chmod 0440 /etc/sudoers.d/pp-pipeline-app \
    && chown root:root /etc/sudoers.d/pp-pipeline-app \
    && cp /opt/nexora/bin/deploy-verify /usr/local/bin/deploy-verify \
    && chown root:root /usr/local/bin/deploy-verify \
    && chmod 0755 /usr/local/bin/deploy-verify \
    && chown root:pipeline-app /opt/nexora/hooks \
    && chown root:pipeline-app /opt/nexora/hooks/verify.sh \
    && chmod 0775 /opt/nexora/hooks \
    && chmod 0775 /opt/nexora/hooks/verify.sh \
    && cp /root/.s05-stage/s05_flag.txt  /root/s05_flag.txt \
    && cp /root/.s05-stage/s06_pivot.txt /root/s06_pivot.txt \
    && chmod 0600 /root/s05_flag.txt /root/s06_pivot.txt \
    && chown root:root /root/s05_flag.txt /root/s06_pivot.txt \
    && rm -rf /root/.s05-stage

COPY scripts/entrypoint.sh \
    /usr/local/bin/pp-entrypoint

# ==========================================================
# Recursive permission hardening
# ==========================================================
# Applies to application source and helper binaries.
# Explicitly excludes:
#   /opt/nexora/private  (S04 flag; owned by pipeline-app)
#   /opt/nexora/hooks    (S05 hook; group-writable by pipeline-app)
#
# The hooks directory is re-asserted with the correct
# group ownership and mode AFTER the recursive chown so the
# S05 trust-boundary remains intact.
#
# IMPORTANT: the final two lines must be 0775, not 0664.
# 0664 has no execute bit and deploy-verify will refuse it.
#
RUN chmod 0755 /usr/local/bin/pp-entrypoint \
    && chown -R root:root /opt/nexora \
    && find /opt/nexora \
         -type d \
         -not -path '/opt/nexora/private*' \
         -not -path '/opt/nexora/hooks*' \
         -exec chmod 0755 {} \; \
    && find /opt/nexora \
         -type f \
         -not -path '/opt/nexora/private/*' \
         -not -path '/opt/nexora/bin/*' \
         -not -path '/opt/nexora/hooks/*' \
         -exec chmod 0644 {} \; \
    && chown -R pipeline-app:pipeline-app /opt/nexora/private \
    && chmod 0700 /opt/nexora/private \
    && find /opt/nexora/private -type f -exec chmod 0600 {} \; \
    && chown root:pipeline-app /opt/nexora/hooks \
    && chown root:pipeline-app /opt/nexora/hooks/verify.sh \
    && chmod 0775 /opt/nexora/hooks \
    && chmod 0775 /opt/nexora/hooks/verify.sh

EXPOSE 5000

ENTRYPOINT ["/usr/local/bin/pp-entrypoint"]