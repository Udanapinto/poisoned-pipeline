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
COPY bin/ /opt/nexora/bin/
COPY config/ /opt/nexora/config/
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
COPY sudoers/pp-pipeline-app /etc/sudoers.d/pp-pipeline-app
COPY hooks/ /opt/nexora/hooks/
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

# ==========================================================
# S06 - Behind the Firewall materials
# ==========================================================
#
# sshd drop-in: password auth disabled globally, re-enabled
# only for the pivot account. AllowTcpForwarding is required
# for the S06 SOCKS tunnel. ForceCommand /usr/sbin/nologin
# on the pivot user means it can only be used as a tunnel
# endpoint, not as an interactive shell.
#
COPY ssh/pp-pipeline.conf /etc/ssh/sshd_config.d/pp-pipeline.conf

RUN chmod 0644 /etc/ssh/sshd_config.d/pp-pipeline.conf \
    && chown root:root /etc/ssh/sshd_config.d/pp-pipeline.conf \
    && rm -f /etc/ssh/ssh_host_*_key /etc/ssh/ssh_host_*_key.pub \
    && mkdir -p /run/sshd \
    && chmod 0755 /run/sshd

# Pivot account creation.
#
# Idempotent: if the user already exists for any reason, it is
# not recreated. The password hash is staged privately by
# scripts/build-application.sh at
# application/.s06-private/pivot_pass.txt.
#
COPY .s06-private/pivot_pass.txt /root/.s06-stage/pivot_pass.txt

RUN PIVOT_HASH="$(cat /root/.s06-stage/pivot_pass.txt)" \
    && (id pivot >/dev/null 2>&1 || useradd \
            --create-home \
            --shell /usr/sbin/nologin \
            --comment "S06 pivot account" \
            pivot) \
    && echo "pivot:${PIVOT_HASH}" | chpasswd -e \
    && rm -rf /root/.s06-stage \
    && chmod 0700 /home/pivot

# ==========================================================
# Entrypoint
# ==========================================================
COPY scripts/entrypoint.sh \
    /usr/local/bin/pp-entrypoint

# ==========================================================
# Recursive permission hardening
# ==========================================================
# Excludes:
#   /opt/nexora/private  (S04 flag; owned by pipeline-app)
#   /opt/nexora/hooks    (S05 hook; group-writable)
#
# The hooks block is re-asserted last so the S05 trust
# boundary stays intact. It must be 0775 so deploy-verify
# accepts it as executable.
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