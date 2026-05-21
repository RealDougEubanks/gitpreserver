#!/usr/bin/env bash
#
# GitPreserver — single-entrypoint wrapper for cron.
#
# Runs the three-stage backup pipeline (mirror -> metadata -> sync) under a
# flock so overlapping schedules cannot corrupt a snapshot in progress.
# Exits non-zero if any stage fails; cron should capture stderr/stdout.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

LOCK_FILE="${GITPRESERVER_LOCK_FILE:-${SCRIPT_DIR}/.gitpreserver.lock}"
COMPOSE=(docker compose)

log() { printf '[gitpreserver] %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }

run_pipeline() {
    log "Starting backup run (pid $$)"
    "${COMPOSE[@]}" run --rm mirror
    "${COMPOSE[@]}" run --rm metadata
    "${COMPOSE[@]}" run --rm sync
    log "Backup run complete"
}

# Re-exec under flock unless we already hold the lock. -n exits immediately if
# another run is in progress; -E 75 (EX_TEMPFAIL) signals "try again later" to
# cron mail handlers without flagging a hard error.
if [[ "${GITPRESERVER_LOCKED:-}" != "1" ]]; then
    if ! command -v flock >/dev/null 2>&1; then
        log "WARNING: flock not found on PATH; running without overlap protection."
        run_pipeline
        exit 0
    fi
    exec env GITPRESERVER_LOCKED=1 flock -n -E 75 "${LOCK_FILE}" "$0" "$@"
fi

run_pipeline
