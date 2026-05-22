#!/usr/bin/env bash
#
# In-container orchestrator. Runs mirror -> metadata -> sync sequentially
# inside a single container. Used by standalone `docker run` invocations
# (unRAID Community Applications, Synology Container Manager, plain
# `docker run dougeubanks/gitpreserver`, etc.).
#
# The docker-compose pipeline does NOT call this script — it runs each
# stage in its own container so the per-stage `depends_on` ordering and
# rclone.conf bind-mount stay scoped to the sync container only.
#
# A non-zero exit from any stage aborts the run.

set -euo pipefail

log() { printf '[gitpreserver] %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }

log "Stage 1/3: mirror"
mirror.sh

log "Stage 2/3: metadata"
metadata.sh

log "Stage 3/3: sync"
sync.sh

log "All stages complete."
