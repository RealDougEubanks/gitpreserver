FROM debian:bookworm-slim

ARG GHORG_VERSION=1.9.10
ARG GH_VERSION=2.47.0
ARG RCLONE_VERSION=1.67.0
ARG PUID=1000
ARG PGID=1000

LABEL org.opencontainers.image.title="GitPreserver" \
      org.opencontainers.image.description="A life preserver for your git repositories." \
      org.opencontainers.image.source="https://github.com/RealDougEubanks/gitpreserver" \
      org.opencontainers.image.licenses="MIT"

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      curl \
      git \
      jq \
      tini \
      unzip \
 && rm -rf /var/lib/apt/lists/*

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
RUN groupadd --system --gid "${PGID}" gitpreserver \
 && useradd --system --uid "${PUID}" --gid "${PGID}" \
      --home-dir /home/gitpreserver --create-home \
      --shell /usr/sbin/nologin gitpreserver \
 && mkdir -p /backups /home/gitpreserver/.config/rclone \
 && chown -R gitpreserver:gitpreserver /backups /home/gitpreserver

COPY --chown=root:root --chmod=0755 backup/ /usr/local/bin/

ENV HOME=/home/gitpreserver \
    RCLONE_CONFIG=/home/gitpreserver/.config/rclone/rclone.conf \
    GH_CONFIG_DIR=/home/gitpreserver/.config/gh

USER gitpreserver
WORKDIR /backups

ENTRYPOINT ["/usr/bin/tini", "--"]
