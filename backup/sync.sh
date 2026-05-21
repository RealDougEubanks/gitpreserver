#!/usr/bin/env bash
set -euo pipefail

log() { echo "[gitpreserver] $(date +%Y-%m-%dT%H:%M:%S) $*"; }

BACKUP_DIR="${GITPRESERVER_BACKUP_DIR:-/backups}"
RCLONE_REMOTE="${GITPRESERVER_RCLONE_REMOTE:-}"
RCLONE_PATH="${GITPRESERVER_RCLONE_PATH:-gitpreserver-backups}"
RCLONE_TRANSFERS="${GITPRESERVER_RCLONE_TRANSFERS:-4}"
ENCRYPT="${GITPRESERVER_ENCRYPT:-false}"
CRYPT_REMOTE="${GITPRESERVER_CRYPT_REMOTE:-}"
LOG_LEVEL="${GITPRESERVER_LOG_LEVEL:-info}"
RETENTION_DAYS="${GITPRESERVER_RETENTION_DAYS:-30}"
DRY_RUN="${GITPRESERVER_DRY_RUN:-false}"

# ---- Remote sync --------------------------------------------------------

if [[ -z "${RCLONE_REMOTE}" ]]; then
    log "GITPRESERVER_RCLONE_REMOTE is not set — skipping remote sync (local backup only)."
else
    if [[ "${ENCRYPT}" == "true" ]]; then
        if [[ -z "${CRYPT_REMOTE}" ]]; then
            log "ERROR: GITPRESERVER_ENCRYPT=true but GITPRESERVER_CRYPT_REMOTE is not set."
            exit 1
        fi
        ACTIVE_REMOTE="${CRYPT_REMOTE}"
    else
        ACTIVE_REMOTE="${RCLONE_REMOTE}"
    fi

    DEST="${ACTIVE_REMOTE}:${RCLONE_PATH}"
    RCLONE_LOG_LEVEL=$(echo "${LOG_LEVEL}" | tr '[:lower:]' '[:upper:]')

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN: rclone sync ${BACKUP_DIR} → ${DEST}"
        rclone sync "${BACKUP_DIR}" "${DEST}" \
            --transfers="${RCLONE_TRANSFERS}" \
            --log-level="${RCLONE_LOG_LEVEL}" \
            --dry-run
    else
        log "Syncing ${BACKUP_DIR} → ${DEST}"
        rclone sync "${BACKUP_DIR}" "${DEST}" \
            --transfers="${RCLONE_TRANSFERS}" \
            --log-level="${RCLONE_LOG_LEVEL}"
        log "Sync complete."
    fi
fi

# ---- Local retention pruning -------------------------------------------

if [[ "${RETENTION_DAYS}" -gt 0 ]]; then
    log "Pruning local snapshots older than ${RETENTION_DAYS} days"
    find "${BACKUP_DIR}" \
        -maxdepth 1 \
        -type d \
        -name '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' \
        -mtime +"${RETENTION_DAYS}" \
        -print \
        ${DRY_RUN:+} | while read -r old_dir; do
            if [[ "${DRY_RUN}" == "true" ]]; then
                log "DRY RUN: would remove ${old_dir}"
            else
                log "Removing ${old_dir}"
                rm -rf "${old_dir}"
            fi
        done
else
    log "Retention pruning disabled (GITPRESERVER_RETENTION_DAYS=0)."
fi
