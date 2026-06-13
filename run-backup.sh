#!/usr/bin/env bash
#
# GitPreserver — single-entrypoint wrapper for cron and ad-hoc runs.
#
# Usage:
#   ./run-backup.sh                       # use .env defaults
#   ./run-backup.sh /path/to/backups      # override host backup directory
#   ./run-backup.sh /path/... --no-sync   # local backup only, skip rclone
#   ./run-backup.sh --dry-run             # validate config without writing
#   ./run-backup.sh --help
#
# All options can be combined. Positional DEST_PATH overrides
# GITPRESERVER_HOST_BACKUP_DIR for this run only and is created if it
# doesn't exist.
#
# Runs the three-stage pipeline (mirror -> metadata -> sync) under a
# flock so overlapping schedules cannot corrupt a snapshot in progress.
# Exits non-zero if any stage fails.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

LOCK_FILE="${GITPRESERVER_LOCK_FILE:-${SCRIPT_DIR}/.gitpreserver.lock}"

# Component label for the structured logger: this wrapper lives at the repo
# root, so derive a name explicitly rather than from the script path.
# shellcheck disable=SC2034  # consumed by the sourced lib/log.sh, not in this file
GITPRESERVER_LOG_COMPONENT="run-backup"
source "${SCRIPT_DIR}/backup/lib/log.sh"

usage() {
    cat <<'EOF'
Usage: run-backup.sh [DEST_PATH] [OPTIONS]

Runs the GitPreserver backup pipeline: mirror -> metadata -> sync.

Arguments:
  DEST_PATH         Host directory to write backups to. Overrides
                    GITPRESERVER_HOST_BACKUP_DIR for this run only.
                    Created if it does not exist.

Options:
  --no-sync         Skip the rclone sync stage. Use for local-only
                    backups to a NAS, external disk, or any host path.
  --dry-run         Show what would happen without writing repos or
                    pushing to a remote. Implies GITPRESERVER_DRY_RUN=true.
  -h, --help        Show this help and exit.

Examples:
  # Default: read everything from .env
  ./run-backup.sh

  # One-off local backup to an external disk
  ./run-backup.sh /Volumes/Backup/github --no-sync

  # Cron: weekly local backup to a NAS mount, no rclone
  0 2 * * 0 /opt/gitpreserver/run-backup.sh /mnt/nas/github --no-sync
EOF
}

DEST_PATH=""
NO_SYNC=false
CLI_DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --no-sync)
            NO_SYNC=true
            shift
            ;;
        --dry-run)
            CLI_DRY_RUN=true
            shift
            ;;
        --)
            shift
            break
            ;;
        -*)
            log_error "ERROR: unknown option '$1'. Try --help."
            exit 2
            ;;
        *)
            if [[ -n "${DEST_PATH}" ]]; then
                log_error "ERROR: more than one destination path given ('${DEST_PATH}' and '$1')."
                exit 2
            fi
            DEST_PATH="$1"
            shift
            ;;
    esac
done

if [[ -n "${DEST_PATH}" ]]; then
    # Resolve to an absolute path so docker compose doesn't bind-mount
    # something relative to compose's cwd (which is SCRIPT_DIR here, but
    # being explicit avoids surprises if the user runs from elsewhere).
    mkdir -p "${DEST_PATH}"
    DEST_PATH="$(cd "${DEST_PATH}" && pwd)"
    export GITPRESERVER_HOST_BACKUP_DIR="${DEST_PATH}"
    log_info "Backup destination: ${DEST_PATH}"
fi

# Honor either the CLI flag or the shell environment variable. Shell env
# vars set on the command line (e.g. `GITPRESERVER_DRY_RUN=true ./run-backup.sh`)
# would otherwise be silently dropped because `docker compose run` does not
# inherit the parent shell's environment for container env, only for compose's
# own variable substitution. Threading it through -e below ensures parity
# between `./run-backup.sh --dry-run` and `GITPRESERVER_DRY_RUN=true ./run-backup.sh`.
if [[ "${CLI_DRY_RUN}" == "true" || "${GITPRESERVER_DRY_RUN:-}" == "true" ]]; then
    CLI_DRY_RUN=true
    export GITPRESERVER_DRY_RUN=true
fi

# Build a list of `-e KEY=VALUE` pairs that apply to every stage. Storing
# them as a newline-delimited string avoids bash 3.2's well-known empty-array
# behavior under `set -u`.
shared_env=""
append_env() { shared_env+="$1"$'\n'; }

if [[ "${CLI_DRY_RUN}" == "true" ]]; then
    append_env "-e"
    append_env "GITPRESERVER_DRY_RUN=true"
fi

# Resolve the Docker Compose command once. Modern installs ship the v2 plugin
# ("docker compose"); older ones have the v1 standalone binary
# ("docker-compose"). Stored as an array so it expands as a command prefix.
if docker compose version >/dev/null 2>&1; then
    COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE=(docker-compose)
else
    log_error "ERROR: neither 'docker compose' (v2 plugin) nor 'docker-compose' (v1) is available on PATH."
    exit 1
fi

# Read shared_env into an args array on use (works fine when empty under -u).
# --no-deps: this script runs mirror -> metadata -> sync sequentially itself,
# so Compose must NOT re-trigger each stage's `depends_on` (which would re-run
# mirror when we invoke metadata, etc.). The compose-file depends_on ordering
# is for `docker compose up`; here we own the ordering.
compose_run_args() {
    local args=()
    while IFS= read -r line; do
        [[ -n "${line}" ]] && args+=("${line}")
    done <<< "${shared_env}"
    "${COMPOSE[@]}" run --rm --no-deps "${args[@]+"${args[@]}"}" "$@"
}

run_pipeline() {
    log_info "Starting backup run (pid $$)"
    # Build once up front so all three stages share a freshly built image.
    # Docker's layer cache makes this near-instant when nothing changed;
    # without it, edits to backup/*.sh or docker/Dockerfile silently run
    # the previously-built image and look like the change had no effect.
    log_info "Ensuring image is up to date (${COMPOSE[*]} build)"
    # A quiet build keeps scheduled/cron logs clean, but older Docker/Compose
    # releases don't accept `--quiet` on `build` (they error with
    # "unknown flag: --quiet"). Probe for support and fall back to a normal
    # build so the pipeline runs everywhere.
    if "${COMPOSE[@]}" build --help 2>/dev/null | grep -q -- '--quiet'; then
        "${COMPOSE[@]}" build --quiet
    else
        "${COMPOSE[@]}" build
    fi
    compose_run_args mirror
    compose_run_args metadata

    if [[ "${NO_SYNC}" == "true" ]]; then
        # Skip the sync service entirely: it bind-mounts rclone.conf, which
        # the user may not have configured. Run sync.sh under the mirror
        # service (same image, no rclone.conf mount) with an empty remote
        # so only the retention-prune step executes.
        log_info "Skipping rclone sync (--no-sync); running retention prune only."
        compose_run_args \
            -e GITPRESERVER_RCLONE_REMOTE= \
            --entrypoint sync.sh \
            mirror
    else
        compose_run_args sync
    fi

    log_info "Backup run complete"
}

# Re-exec under flock unless we already hold the lock. -n exits immediately
# if another run is in progress; -E 75 (EX_TEMPFAIL) signals "try again
# later" to cron mail handlers without flagging a hard error.
if [[ "${GITPRESERVER_LOCKED:-}" != "1" ]]; then
    if ! command -v flock >/dev/null 2>&1; then
        log_warn "WARNING: flock not found on PATH; running without overlap protection."
        run_pipeline
        exit 0
    fi
    exec env GITPRESERVER_LOCKED=1 flock -n -E 75 "${LOCK_FILE}" "$0" "$@"
fi

run_pipeline
