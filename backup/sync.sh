#!/usr/bin/env bash
set -euo pipefail

log() { printf '[gitpreserver] %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }

BACKUP_DIR="${GITPRESERVER_BACKUP_DIR:-/backups}"
RCLONE_REMOTE="${GITPRESERVER_RCLONE_REMOTE:-}"
RCLONE_PATH="${GITPRESERVER_RCLONE_PATH:-gitpreserver-backups}"
RCLONE_TRANSFERS="${GITPRESERVER_RCLONE_TRANSFERS:-4}"
ENCRYPT="${GITPRESERVER_ENCRYPT:-false}"
CRYPT_REMOTE="${GITPRESERVER_CRYPT_REMOTE:-}"
LOG_LEVEL="${GITPRESERVER_LOG_LEVEL:-info}"
RETENTION_DAYS="${GITPRESERVER_RETENTION_DAYS:-30}"
DRY_RUN="${GITPRESERVER_DRY_RUN:-false}"

if ! [[ "${RETENTION_DAYS}" =~ ^[0-9]+$ ]]; then
    log "ERROR: GITPRESERVER_RETENTION_DAYS must be a non-negative integer (got '${RETENTION_DAYS}')."
    exit 1
fi

if ! [[ "${RCLONE_TRANSFERS}" =~ ^[0-9]+$ ]] || (( RCLONE_TRANSFERS == 0 )); then
    log "ERROR: GITPRESERVER_RCLONE_TRANSFERS must be a positive integer (got '${RCLONE_TRANSFERS}')."
    exit 1
fi

# ---- Remote sync --------------------------------------------------------

if [[ -z "${RCLONE_REMOTE}" ]]; then
    log "GITPRESERVER_RCLONE_REMOTE is not set -- skipping remote sync (local backup only)."
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
    RCLONE_LOG_LEVEL=$(printf '%s' "${LOG_LEVEL}" | tr '[:lower:]' '[:upper:]')

    rclone_args=(
        sync "${BACKUP_DIR}" "${DEST}"
        --transfers="${RCLONE_TRANSFERS}"
        --log-level="${RCLONE_LOG_LEVEL}"
    )

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN: rclone sync ${BACKUP_DIR} -> ${DEST}"
        rclone_args+=(--dry-run)
    else
        log "Syncing ${BACKUP_DIR} -> ${DEST}"
    fi

    rclone "${rclone_args[@]}"

    [[ "${DRY_RUN}" == "true" ]] || log "Sync complete."
fi

# ---- Local retention pruning -------------------------------------------

if (( RETENTION_DAYS > 0 )); then
    log "Pruning local snapshots older than ${RETENTION_DAYS} days"
    # -print0 / read -d '' protects against unusual directory names.
    # -maxdepth 1 keeps us out of the per-day repo contents.
    while IFS= read -r -d '' old_dir; do
        if [[ "${DRY_RUN}" == "true" ]]; then
            log "DRY RUN: would remove ${old_dir}"
        else
            log "Removing ${old_dir}"
            rm -rf -- "${old_dir}"
        fi
    done < <(find "${BACKUP_DIR}" \
        -mindepth 1 -maxdepth 1 \
        -type d \
        -name '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' \
        -mtime +"${RETENTION_DAYS}" \
        -print0)
else
    log "Retention pruning disabled (GITPRESERVER_RETENTION_DAYS=0)."
fi
