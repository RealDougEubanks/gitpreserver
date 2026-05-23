FROM debian:bookworm-slim

# pipefail catches mid-pipeline failures in `curl | tar` style installs below.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG GHORG_VERSION=1.9.10
ARG GH_VERSION=2.47.0
ARG RCLONE_VERSION=1.67.0
ARG SUPERCRONIC_VERSION=0.2.33
ARG PUID=1000
ARG PGID=1000

LABEL org.opencontainers.image.title="GitPreserver" \
      org.opencontainers.image.description="A life preserver for your git repositories." \
      org.opencontainers.image.source="https://github.com/RealDougEubanks/gitpreserver" \
      org.opencontainers.image.documentation="https://github.com/RealDougEubanks/gitpreserver#readme" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="Doug Eubanks" \
      org.gitpreserver.dependencies="ghorg=${GHORG_VERSION} (Apache-2.0); gh=${GH_VERSION} (MIT); rclone=${RCLONE_VERSION} (MIT); tini (MIT); jq (MIT); git (GPL-2.0); debian:bookworm-slim"

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      curl \
      git \
      gosu \
      jq \
      python3 \
      tini \
      unzip \
 && rm -rf /var/lib/apt/lists/*

# Install supercronic — container-native cron daemon (daemon mode scheduler)
RUN set -eux \
 && ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') \
 && curl -fsSL \
      "https://github.com/aptible/supercronic/releases/download/v${SUPERCRONIC_VERSION}/supercronic-linux-${ARCH}" \
      -o /usr/local/bin/supercronic \
 && chmod +x /usr/local/bin/supercronic

# Install rclone — uname -m: x86_64/aarch64 → rclone naming: amd64/arm64
RUN set -eux \
 && ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') \
 && curl -fsSL \
      "https://downloads.rclone.org/v${RCLONE_VERSION}/rclone-v${RCLONE_VERSION}-linux-${ARCH}.zip" \
      -o /tmp/rclone.zip \
 && unzip /tmp/rclone.zip -d /tmp/rclone \
 && mv "/tmp/rclone/rclone-v${RCLONE_VERSION}-linux-${ARCH}/rclone" /usr/local/bin/rclone \
 && chmod +x /usr/local/bin/rclone \
 && rm -rf /tmp/rclone /tmp/rclone.zip

# Install gh CLI — dpkg arch: amd64/arm64
RUN set -eux \
 && ARCH=$(dpkg --print-architecture) \
 && curl -fsSL \
      "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${ARCH}.tar.gz" \
      | tar -xz -C /tmp \
 && mv "/tmp/gh_${GH_VERSION}_linux_${ARCH}/bin/gh" /usr/local/bin/gh \
 && chmod +x /usr/local/bin/gh \
 && rm -rf "/tmp/gh_${GH_VERSION}_linux_${ARCH}"

# Install ghorg — release assets use capital "Linux" and uname -m arch (x86_64/arm64)
RUN set -eux \
 && ARCH=$(uname -m | sed 's/aarch64/arm64/') \
 && curl -fsSL \
      "https://github.com/gabrie30/ghorg/releases/download/v${GHORG_VERSION}/ghorg_${GHORG_VERSION}_Linux_${ARCH}.tar.gz" \
      -o /tmp/ghorg.tar.gz \
 && tar -xzf /tmp/ghorg.tar.gz -C /usr/local/bin ghorg \
 && chmod +x /usr/local/bin/ghorg \
 && rm -f /tmp/ghorg.tar.gz

# Non-root runtime user. Host bind mounts must be writable by this UID/GID
# (override at build time with --build-arg PUID/PGID, or at runtime with `user:` in compose).
RUN groupadd --gid "${PGID}" gitpreserver \
 && useradd --uid "${PUID}" --gid "${PGID}" \
      --home-dir /home/gitpreserver --create-home \
      --shell /usr/sbin/nologin gitpreserver \
 && mkdir -p /backups /home/gitpreserver/.config/rclone \
 && chown -R gitpreserver:gitpreserver /backups /home/gitpreserver

COPY --chown=root:root --chmod=0755 backup/ /usr/local/bin/
COPY --chown=root:root --chmod=0755 docker/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chown=root:root --chmod=0755 docker/daemon-start.sh /usr/local/bin/daemon-start.sh
COPY --chown=root:root --chmod=0755 docker/webserver.py /usr/local/bin/webserver.py

ENV HOME=/home/gitpreserver \
    RCLONE_CONFIG=/home/gitpreserver/.config/rclone/rclone.conf \
    GH_CONFIG_DIR=/home/gitpreserver/.config/gh

# Container starts as root so entrypoint.sh can usermod/groupmod the
# gitpreserver user to match host PUID/PGID, then drops privileges via
# gosu. The workload (ghorg, gh, rclone) never runs as root.
# Port for the web UI (daemon mode only). Can be overridden via GITPRESERVER_WEB_PORT.
EXPOSE 6033

WORKDIR /backups

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]

# Default command runs the full pipeline in a single container. docker-compose
# overrides this with per-service `command:` entries (mirror.sh / metadata.sh /
# sync.sh) and is unaffected. Standalone `docker run` users — unRAID,
# Synology Container Manager, ad-hoc invocations — get a working backup
# without having to know the stage names.
CMD ["run-stages.sh"]
