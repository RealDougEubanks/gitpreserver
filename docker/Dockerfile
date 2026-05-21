FROM debian:bookworm-slim

ARG GHORG_VERSION=1.9.10
ARG GH_VERSION=2.47.0
ARG RCLONE_VERSION=1.67.0

LABEL org.opencontainers.image.title="GitPreserver" \
      org.opencontainers.image.description="A life preserver for your git repositories." \
      org.opencontainers.image.source="https://github.com/dougeubanks/gitpreserver" \
      org.opencontainers.image.licenses="MIT"

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      curl \
      git \
      jq \
      unzip \
 && rm -rf /var/lib/apt/lists/*

# Install rclone — handles amd64 and arm64 via uname -m
RUN set -eux \
 && ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') \
 && curl -fsSL \
      "https://downloads.rclone.org/v${RCLONE_VERSION}/rclone-v${RCLONE_VERSION}-linux-${ARCH}.zip" \
      -o /tmp/rclone.zip \
 && unzip /tmp/rclone.zip -d /tmp/rclone \
 && mv "/tmp/rclone/rclone-v${RCLONE_VERSION}-linux-${ARCH}/rclone" /usr/local/bin/rclone \
 && chmod +x /usr/local/bin/rclone \
 && rm -rf /tmp/rclone /tmp/rclone.zip

# Install gh CLI
RUN set -eux \
 && ARCH=$(dpkg --print-architecture) \
 && curl -fsSL \
      "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${ARCH}.tar.gz" \
      | tar -xz -C /tmp \
 && mv "/tmp/gh_${GH_VERSION}_linux_${ARCH}/bin/gh" /usr/local/bin/gh \
 && chmod +x /usr/local/bin/gh \
 && rm -rf "/tmp/gh_${GH_VERSION}_linux_${ARCH}"

# Install ghorg
RUN set -eux \
 && ARCH=$(uname -m) \
 && curl -fsSL \
      "https://github.com/gabrie30/ghorg/releases/download/v${GHORG_VERSION}/ghorg_${GHORG_VERSION}_linux_${ARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin ghorg \
 && chmod +x /usr/local/bin/ghorg

COPY backup/ /usr/local/bin/
RUN chmod +x \
      /usr/local/bin/mirror.sh \
      /usr/local/bin/metadata.sh \
      /usr/local/bin/sync.sh

WORKDIR /backups
