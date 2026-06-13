#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"

BACKUP_DIR="${GITPRESERVER_BACKUP_DIR:-/backups}"
RCLONE_REMOTES="${GITPRESERVER_RCLONE_REMOTE:-}"
RCLONE_PATH="${GITPRESERVER_RCLONE_PATH:-gitpreserver-backups}"
RCLONE_TRANSFERS="${GITPRESERVER_RCLONE_TRANSFERS:-4}"
ENCRYPT="${GITPRESERVER_ENCRYPT:-false}"
CRYPT_REMOTES="${GITPRESERVER_CRYPT_REMOTE:-}"
LOG_LEVEL="${GITPRESERVER_LOG_LEVEL:-info}"
RETENTION_DAYS="${GITPRESERVER_RETENTION_DAYS:-30}"
DRY_RUN="${GITPRESERVER_DRY_RUN:-false}"

# Remotes that failed to sync. Declared up front so the partial-failure
# reporting block below works even when no remotes are configured.
failed_remotes=()

if ! [[ "${RETENTION_DAYS}" =~ ^[0-9]+$ ]]; then
    log_error "ERROR: GITPRESERVER_RETENTION_DAYS must be a non-negative integer (got '${RETENTION_DAYS}')."
    exit 1
fi

if ! [[ "${RCLONE_TRANSFERS}" =~ ^[0-9]+$ ]] || (( RCLONE_TRANSFERS == 0 )); then
    log_error "ERROR: GITPRESERVER_RCLONE_TRANSFERS must be a positive integer (got '${RCLONE_TRANSFERS}')."
    exit 1
fi

# ---- Remote sync --------------------------------------------------------

if [[ -z "${RCLONE_REMOTES}" ]]; then
    log_info "GITPRESERVER_RCLONE_REMOTE is not set -- skipping remote sync (local backup only)."
else
    RCLONE_LOG_LEVEL=$(printf '%s' "${LOG_LEVEL}" | tr '[:lower:]' '[:upper:]')

    # Split comma-separated remote lists into arrays.
    IFS=',' read -ra remote_list   <<< "${RCLONE_REMOTES}"
    IFS=',' read -ra crypt_list    <<< "${CRYPT_REMOTES:-}"

    # When encryption is enabled, require a crypt remote for every plain remote.
    if [[ "${ENCRYPT}" == "true" ]]; then
        if [[ -z "${CRYPT_REMOTES}" ]]; then
            log_error "ERROR: GITPRESERVER_ENCRYPT=true but GITPRESERVER_CRYPT_REMOTE is not set."
            exit 1
        fi
        if (( ${#crypt_list[@]} != ${#remote_list[@]} )); then
            log_error "ERROR: GITPRESERVER_CRYPT_REMOTE has ${#crypt_list[@]} entries but GITPRESERVER_RCLONE_REMOTE has ${#remote_list[@]}. They must match 1-to-1."
            exit 1
        fi
    fi

    for i in "${!remote_list[@]}"; do
        remote="${remote_list[$i]}"
        # Trim whitespace
        remote="${remote#"${remote%%[![:space:]]*}"}"
        remote="${remote%"${remote##*[![:space:]]}"}"
        [[ -z "${remote}" ]] && continue

        if [[ "${ENCRYPT}" == "true" ]]; then
            crypt="${crypt_list[$i]}"
            crypt="${crypt#"${crypt%%[![:space:]]*}"}"
            crypt="${crypt%"${crypt##*[![:space:]]}"}"
            ACTIVE_REMOTE="${crypt}"
        else
            ACTIVE_REMOTE="${remote}"
        fi

        DEST="${ACTIVE_REMOTE}:${RCLONE_PATH}"

        rclone_args=(
            sync "${BACKUP_DIR}" "${DEST}"
            --transfers="${RCLONE_TRANSFERS}"
            --log-level="${RCLONE_LOG_LEVEL}"
        )

        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "DRY RUN: rclone sync ${BACKUP_DIR} -> ${DEST}"
            rclone_args+=(--dry-run)
        else
            log_info "Syncing ${BACKUP_DIR} -> ${DEST}"
        fi

        # Run each remote independently. A failure here must NOT abort the
        # loop (errexit would skip remaining remotes and retention pruning),
        # so we trap the non-zero status, record the remote, and keep going.
        if rclone "${rclone_args[@]}"; then
            [[ "${DRY_RUN}" == "true" ]] || log_info "Sync to ${DEST} complete."
        else
            log_error "ERROR: rclone sync to ${DEST} failed."
            failed_remotes+=("${ACTIVE_REMOTE}")
        fi
    done
fi

# ---- Local retention pruning -------------------------------------------

if (( RETENTION_DAYS > 0 )); then
    log_info "Pruning local snapshots older than ${RETENTION_DAYS} days"
    while IFS= read -r -d '' old_dir; do
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "DRY RUN: would remove ${old_dir}"
        else
            log_info "Removing ${old_dir}"
            rm -rf -- "${old_dir}"
        fi
    done < <(find "${BACKUP_DIR}" \
        -mindepth 1 -maxdepth 1 \
        -type d \
        -name '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' \
        -mtime +"${RETENTION_DAYS}" \
        -print0)
else
    log_info "Retention pruning disabled (GITPRESERVER_RETENTION_DAYS=0)."
fi

# ---- Partial-failure reporting -----------------------------------------
# Retention pruning above always runs, even when one or more remotes failed.
# We surface failures here so cron/daemon status reflects partial failure and
# the notification layer can read the list. Exit non-zero if anything failed.

if (( ${#failed_remotes[@]} > 0 )); then
    failed_csv=$(IFS=','; printf '%s' "${failed_remotes[*]}")
    log_error "ERROR: ${#failed_remotes[@]} remote(s) failed to sync: ${failed_csv}"
    # Make the failed-remote list available to the notification payload.
    # A status file is the least-coupled option (sync.sh and notify.sh are
    # separate processes); fall back to stderr if the dir is not writable.
    if ! printf '%s\n' "${failed_csv}" > "${BACKUP_DIR}/.gitpreserver-failed-remotes" 2>/dev/null; then
        printf 'gitpreserver: failed remotes: %s\n' "${failed_csv}" >&2
    fi
    exit 1
fi
