ARG KALI_BASE_IMAGE=kalilinux/kali-rolling:latest

FROM ${KALI_BASE_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    git \
    jq \
    python3 \
    python3-pip \
    python3-requests \
    nmap \
    proxychains4 \
    openssh-client \
    postgresql-client \
    netcat-openbsd \
    sshpass \
    grep \
    gawk \
    diffutils \
    tree \
    unzip \
    zip \
    vim \
    less \
    procps \
    iproute2 \
    dnsutils \
    && rm -rf /var/lib/apt/lists/*

# Create the participant account
RUN useradd --create-home --shell /bin/bash --uid 1000 participant

# Working directory for the participant
WORKDIR /home/participant

# Drop into the participant account
USER participant

# Keep the container alive
CMD ["sleep", "infinity"]