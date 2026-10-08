ARG JENKINS_BASE_IMAGE=jenkins/jenkins:lts-jdk21
FROM ${JENKINS_BASE_IMAGE}

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl \
        jq \
        zip \
        unzip \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY plugins.txt /usr/share/jenkins/ref/plugins.txt

RUN jenkins-plugin-cli \
    --plugin-file /usr/share/jenkins/ref/plugins.txt

COPY scripts/seed-build-artifacts.sh \
     /usr/local/bin/pp-seed-build-artifacts

RUN chmod 0755 /usr/local/bin/pp-seed-build-artifacts

USER jenkins