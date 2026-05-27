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

STATUS_FILE="${GITPRESERVER_STATUS_FILE:-/tmp/gitpreserver-status.json}"
CURRENT_STAGE="init"

write_status() {
    local status="$1" message="$2"
    jq -cn \
        --arg s "${status}" \
        --arg m "${message}" \
        --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{status:$s, last_run:$t, message:$m}' \
        > "${STATUS_FILE}" 2>/dev/null || true
}

on_error() {
    local msg="Pipeline aborted during: ${CURRENT_STAGE}"
    write_status "failed" "${msg}"
    notify.sh "failed" "${msg}" || true
}
trap 'on_error' ERR

CURRENT_STAGE="mirror"
write_status "running" "Stage 1/3: mirror"
log "Stage 1/3: mirror"
mirror.sh

CURRENT_STAGE="metadata"
write_status "running" "Stage 2/3: metadata"
log "Stage 2/3: metadata"
metadata.sh

CURRENT_STAGE="sync"
write_status "running" "Stage 3/3: sync"
log "Stage 3/3: sync"
sync.sh

write_status "success" "All stages complete."
log "All stages complete."
notify.sh "success" "All stages complete." || true
