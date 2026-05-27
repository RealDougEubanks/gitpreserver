#!/usr/bin/env bash
#
# GitPreserver — Synology DSM run wrapper.
#
# Called by DSM Task Scheduler (or manually). Reads .env from the same
# directory, then runs the Docker image in oneshot mode.
#
# Usage:
#   ./run-backup.sh              # use .env defaults
#   ./run-backup.sh --dry-run    # validate config without writing
#   ./run-backup.sh --no-sync    # skip rclone sync (local backup only)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
LOCK_FILE="${SCRIPT_DIR}/.gitpreserver.lock"
IMAGE="dougeubanks/gitpreserver:latest"

log() { printf '[gitpreserver] %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }

if [[ ! -f "${ENV_FILE}" ]]; then
    log "ERROR: .env not found at ${ENV_FILE}. Re-run the Package Center installer."
    exit 1
fi

# Load .env — skip blank lines and comments.
while IFS='=' read -r key value; do
    [[ -z "${key}" || "${key}" == \#* ]] && continue
    export "${key}=${value}"
done < <(grep -v '^\s*#' "${ENV_FILE}" | grep -v '^\s*$')

DRY_RUN="${GITPRESERVER_DRY_RUN:-false}"
NO_SYNC=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        --no-sync) NO_SYNC=true; shift ;;
        *) log "ERROR: unknown option '$1'"; exit 2 ;;
    esac
done

run_container() {
    local extra_env=()

    if [[ "${DRY_RUN}" == "true" ]]; then
        extra_env+=(-e GITPRESERVER_DRY_RUN=true)
    fi

    if [[ "${NO_SYNC}" == "true" ]]; then
        extra_env+=(-e GITPRESERVER_RCLONE_REMOTE=)
    fi

    # Pass every GITPRESERVER_* and RCLONE_CONFIG_* variable from the .env.
    local env_args=()
    while IFS= read -r line; do
        [[ -z "${line}" || "${line}" == \#* ]] && continue
        key="${line%%=*}"
        env_args+=(-e "${line}")
    done < <(grep -v '^\s*#' "${ENV_FILE}" | grep -v '^\s*$' \
             | grep -E '^(GITPRESERVER_|RCLONE_CONFIG_)')

    local rclone_vol=()
    if [[ -f "${SCRIPT_DIR}/rclone.conf" ]]; then
        rclone_vol=(-v "${SCRIPT_DIR}/rclone.conf:/home/gitpreserver/.config/rclone/rclone.conf:ro")
    fi

    log "Starting backup ($(date -u))"
    docker run --rm \
        "${env_args[@]}" \
        "${extra_env[@]+"${extra_env[@]}"}" \
        "${rclone_vol[@]+"${rclone_vol[@]}"}" \
        -v "${GITPRESERVER_BACKUP_DIR:-/volume1/gitpreserver-backups}:/backups" \
        "${IMAGE}"
    log "Backup complete."
}

# Prevent overlapping runs via flock.
if [[ "${GITPRESERVER_LOCKED:-}" != "1" ]]; then
    if ! command -v flock &>/dev/null; then
        log "WARNING: flock not found; running without overlap protection."
        run_container
        exit 0
    fi
    exec env GITPRESERVER_LOCKED=1 flock -n -E 75 "${LOCK_FILE}" "$0" "$@"
fi

run_container
