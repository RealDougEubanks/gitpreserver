# =============================================================================
# GitPreserver container image — multi-stage build.
#
# Stage 1 (builder): downloads + extracts the third-party binaries (ghorg, gh,
# rclone, supercronic) using curl/unzip/tar. These tools are needed ONLY to
# fetch and unpack release archives, so they are confined to the builder and
# never land in the runtime layer.
#
# Stage 2 (runtime): debian:bookworm-slim with just the runtime deps
# (git, jq, python3, tini, gosu, ca-certificates) plus the binaries COPYed
# from the builder. No curl/unzip in the shipped image -> smaller attack
# surface and smaller image.
#
# Multi-arch: amd64/arm64. Each download step maps `uname -m` / dpkg arch to
# the upstream asset naming convention at RUN time, so a single Dockerfile
# builds correctly under `docker buildx --platform`.
#
# SECURITY NOTE — checksum verification: every downloaded artifact is verified
# against a pinned SHA256 before use. The *_SHA256_* ARGs below hold the genuine
# per-architecture hashes for the pinned versions, sourced from upstream release
# checksum files (rclone SHA256SUMS, gh/ghorg checksums.txt) and, for supercronic
# (which ships no checksum file), computed from the released binaries. When
# bumping a version, refresh both the version ARG and its two SHA256 ARGs from
# the same upstream sources; the `sha256sum --check` steps enforce them.
# =============================================================================

# -----------------------------------------------------------------------------
# Builder stage
# -----------------------------------------------------------------------------
FROM debian:bookworm-slim AS builder

# pipefail catches mid-pipeline failures in `curl | tar` style installs below.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Pinned tool versions (latest stable as of 2026-06-12).
ARG GHORG_VERSION=1.11.11
ARG GH_VERSION=2.94.0
ARG RCLONE_VERSION=1.74.3
ARG SUPERCRONIC_VERSION=0.2.46

# SHA256 checksums per architecture, from upstream release checksum files
# (supercronic hashes computed from the released binaries — it ships none).
# Refresh these whenever a version ARG above changes.
ARG SUPERCRONIC_SHA256_AMD64=5adff01c5a797663948e656d2b61d10932369ee437eb5cb54fa872b2960f222b
ARG SUPERCRONIC_SHA256_ARM64=c0576a8eb092e3f79108ed0a2155a25c7766af78456e5a6070e54757ef513bfe
ARG RCLONE_SHA256_AMD64=dbee7ccd7a5d617e4ed4cd4555c16669b511abfe8d31164f61be35ac9e999bd2
ARG RCLONE_SHA256_ARM64=8f8d47446e061f80c3256659fe8e21f56d72d96aaefe1275d088ea5eb6b42aa7
ARG GH_SHA256_AMD64=a757f1ba6db18f4de8cbadb244843a5f89bc75b5e7c6fc127d2bd77fbd12ed62
ARG GH_SHA256_ARM64=705a23b70b0f1b7ba4c302fdcef392ce3edaacfa7ce8e85e4d93d72ea800a538
ARG GHORG_SHA256_AMD64=3f479d2e6d376114ddb0a24af4774d2f28eb6a735f5d9f3a2d1847df61d85752
ARG GHORG_SHA256_ARM64=4c7452fdf81730187579359f6a621139252e4fe5c11f2083b850d514c7f0b310

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      tar \
      unzip \
 && rm -rf /var/lib/apt/lists/*

# Install supercronic — container-native cron daemon (daemon mode scheduler)
RUN set -eux \
 && ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') \
 && case "${ARCH}" in \
      amd64) SUM="${SUPERCRONIC_SHA256_AMD64}" ;; \
      arm64) SUM="${SUPERCRONIC_SHA256_ARM64}" ;; \
      *) echo "unsupported arch: ${ARCH}" >&2; exit 1 ;; \
    esac \
 && curl -fsSL \
      "https://github.com/aptible/supercronic/releases/download/v${SUPERCRONIC_VERSION}/supercronic-linux-${ARCH}" \
      -o /tmp/supercronic \
 && echo "${SUM}  /tmp/supercronic" | sha256sum --check --strict - \
 && install -m 0755 /tmp/supercronic /usr/local/bin/supercronic \
 && rm -f /tmp/supercronic

# Install rclone — uname -m: x86_64/aarch64 → rclone naming: amd64/arm64
RUN set -eux \
 && ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') \
 && case "${ARCH}" in \
      amd64) SUM="${RCLONE_SHA256_AMD64}" ;; \
      arm64) SUM="${RCLONE_SHA256_ARM64}" ;; \
      *) echo "unsupported arch: ${ARCH}" >&2; exit 1 ;; \
    esac \
 && curl -fsSL \
      "https://downloads.rclone.org/v${RCLONE_VERSION}/rclone-v${RCLONE_VERSION}-linux-${ARCH}.zip" \
      -o /tmp/rclone.zip \
 && echo "${SUM}  /tmp/rclone.zip" | sha256sum --check --strict - \
 && unzip /tmp/rclone.zip -d /tmp/rclone \
 && install -m 0755 "/tmp/rclone/rclone-v${RCLONE_VERSION}-linux-${ARCH}/rclone" /usr/local/bin/rclone \
 && rm -rf /tmp/rclone /tmp/rclone.zip

# Install gh CLI — dpkg arch: amd64/arm64
RUN set -eux \
 && ARCH=$(dpkg --print-architecture) \
 && case "${ARCH}" in \
      amd64) SUM="${GH_SHA256_AMD64}" ;; \
      arm64) SUM="${GH_SHA256_ARM64}" ;; \
      *) echo "unsupported arch: ${ARCH}" >&2; exit 1 ;; \
    esac \
 && curl -fsSL \
      "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${ARCH}.tar.gz" \
      -o /tmp/gh.tar.gz \
 && echo "${SUM}  /tmp/gh.tar.gz" | sha256sum --check --strict - \
 && tar -xz -C /tmp -f /tmp/gh.tar.gz \
 && install -m 0755 "/tmp/gh_${GH_VERSION}_linux_${ARCH}/bin/gh" /usr/local/bin/gh \
 && rm -rf "/tmp/gh_${GH_VERSION}_linux_${ARCH}" /tmp/gh.tar.gz

# Install ghorg — release assets use capital "Linux" and uname -m arch (x86_64/arm64)
RUN set -eux \
 && ARCH=$(uname -m | sed 's/aarch64/arm64/') \
 && case "${ARCH}" in \
      x86_64) SUM="${GHORG_SHA256_AMD64}" ;; \
      arm64) SUM="${GHORG_SHA256_ARM64}" ;; \
      *) echo "unsupported arch: ${ARCH}" >&2; exit 1 ;; \
    esac \
 && curl -fsSL \
      "https://github.com/gabrie30/ghorg/releases/download/v${GHORG_VERSION}/ghorg_${GHORG_VERSION}_Linux_${ARCH}.tar.gz" \
      -o /tmp/ghorg.tar.gz \
 && echo "${SUM}  /tmp/ghorg.tar.gz" | sha256sum --check --strict - \
 && tar -xzf /tmp/ghorg.tar.gz -C /tmp ghorg \
 && install -m 0755 /tmp/ghorg /usr/local/bin/ghorg \
 && rm -f /tmp/ghorg.tar.gz /tmp/ghorg

# -----------------------------------------------------------------------------
# Runtime stage
# -----------------------------------------------------------------------------
FROM debian:bookworm-slim

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Re-declare versions for the LABEL below (build args do not cross stages).
# Keep in sync with the builder-stage version ARGs above.
ARG GHORG_VERSION=1.11.11
ARG GH_VERSION=2.94.0
ARG RCLONE_VERSION=1.74.3
ARG SUPERCRONIC_VERSION=0.2.46
ARG PUID=1000
ARG PGID=1000

LABEL org.opencontainers.image.title="GitPreserver" \
      org.opencontainers.image.description="A life preserver for your git repositories." \
      org.opencontainers.image.source="https://github.com/RealDougEubanks/gitpreserver" \
      org.opencontainers.image.documentation="https://github.com/RealDougEubanks/gitpreserver#readme" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="Doug Eubanks" \
      org.gitpreserver.dependencies="ghorg=${GHORG_VERSION} (Apache-2.0); gh=${GH_VERSION} (MIT); rclone=${RCLONE_VERSION} (MIT); tini (MIT); jq (MIT); git (GPL-2.0); debian:bookworm-slim"

# Runtime-only dependencies. curl/unzip stay in the builder stage and are not
# shipped, shrinking the runtime image and attack surface.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      git \
      gosu \
      jq \
      python3 \
      tini \
 && rm -rf /var/lib/apt/lists/*

# Third-party binaries built/verified in the builder stage.
COPY --from=builder /usr/local/bin/supercronic /usr/local/bin/supercronic
COPY --from=builder /usr/local/bin/rclone /usr/local/bin/rclone
COPY --from=builder /usr/local/bin/gh /usr/local/bin/gh
COPY --from=builder /usr/local/bin/ghorg /usr/local/bin/ghorg

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
    GH_CONFIG_DIR=/home/gitpreserver/.config/gh \
    GITPRESERVER_WEB_PORT=6033

# Container starts as root so entrypoint.sh can usermod/groupmod the
# gitpreserver user to match host PUID/PGID, then drops privileges via
# gosu. The workload (ghorg, gh, rclone) never runs as root.
# Port for the web UI (daemon mode only). Can be overridden via GITPRESERVER_WEB_PORT.
EXPOSE 6033

# Healthcheck probes the daemon-mode web server's /healthz endpoint. This is
# only meaningful in daemon mode — in one-shot/run-stages mode there is no web
# server, so the probe will fail; orchestrators should disable the healthcheck
# (or it is simply ignored once the one-shot container exits). We use Python's
# stdlib http client (python3 is already a runtime dep) so we don't have to add
# curl back into the slim runtime layer just for the probe.
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD python3 -c "import os,urllib.request,sys; \
port=os.environ.get('GITPRESERVER_WEB_PORT','6033'); \
sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:%s/healthz' % port, timeout=3).status==200 else 1)" \
  || exit 1

WORKDIR /backups

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]

# Default command runs the full pipeline in a single container. docker-compose
# overrides this with per-service `command:` entries (mirror.sh / metadata.sh /
# sync.sh) and is unaffected. Standalone `docker run` users — unRAID,
# Synology Container Manager, ad-hoc invocations — get a working backup
# without having to know the stage names.
CMD ["run-stages.sh"]
