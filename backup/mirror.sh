#!/usr/bin/env bash
set -euo pipefail

log() { printf '[gitpreserver] %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }

: "${GITPRESERVER_TOKEN:?GITPRESERVER_TOKEN is required}"
: "${GITPRESERVER_USERNAME:?GITPRESERVER_USERNAME is required}"

# Validate username — accept only characters the four supported hosts allow.
# Refuses shell metacharacters and path separators before they ever reach ghorg.
if ! [[ "${GITPRESERVER_USERNAME}" =~ ^[A-Za-z0-9._-]+$ ]]; then
    log "ERROR: GITPRESERVER_USERNAME contains invalid characters."
    exit 1
fi

BACKUP_DIR="${GITPRESERVER_BACKUP_DIR:-/backups}"
HOST_TYPE="${GITPRESERVER_HOST_TYPE:-github}"
HOST_URL="${GITPRESERVER_HOST_URL:-}"
DRY_RUN="${GITPRESERVER_DRY_RUN:-false}"
CONCURRENCY="${GITPRESERVER_CONCURRENCY:-4}"

BACKUP_DATE=$(date -u +%Y-%m-%d)
SNAPSHOT_PARENT="${BACKUP_DIR}/${BACKUP_DATE}"
OUTPUT_DIR="${SNAPSHOT_PARENT}/repos"

if [[ "${DRY_RUN}" == "true" ]]; then
    log "DRY RUN: would mirror ${GITPRESERVER_USERNAME} (${HOST_TYPE}) -> ${OUTPUT_DIR}"
    exit 0
fi

mkdir -p "${SNAPSHOT_PARENT}"

log "Starting mirror clone: ${GITPRESERVER_USERNAME} (${HOST_TYPE}) -> ${OUTPUT_DIR}"

# ghorg writes to <--path>/<--output-dir>. --output-dir is a *name*, not a
# path — if you pass an absolute path there, ghorg treats it as a literal
# subdirectory name under $HOME/ghorg/. Use --path for the absolute parent.
#
# Tokens are passed via GHORG_*_TOKEN env vars — never via --token= on the
# command line, which would leak into /proc/<pid>/cmdline and `ps`.
ghorg_args=(
    clone "${GITPRESERVER_USERNAME}"
    --clone-type=user
    --backup
    --path="${SNAPSHOT_PARENT}"
    --output-dir=repos
    --concurrency="${CONCURRENCY}"
)

case "${HOST_TYPE}" in
    github)
        export GHORG_GITHUB_TOKEN="${GITPRESERVER_TOKEN}"
        ;;
    bitbucket)
        export GHORG_BITBUCKET_TOKEN="${GITPRESERVER_TOKEN}"
        ghorg_args+=(--scm=bitbucket)
        ;;
    gitlab)
        export GHORG_GITLAB_TOKEN="${GITPRESERVER_TOKEN}"
        ghorg_args+=(--scm=gitlab)
        if [[ -n "${HOST_URL}" ]]; then
            ghorg_args+=(--base-url="${HOST_URL}")
        fi
        ;;
    gitea)
        : "${HOST_URL:?GITPRESERVER_HOST_URL is required for host type 'gitea'}"
        export GHORG_GITEA_TOKEN="${GITPRESERVER_TOKEN}"
        ghorg_args+=(--scm=gitea --base-url="${HOST_URL}")
        ;;
    *)
        log "ERROR: unsupported GITPRESERVER_HOST_TYPE '${HOST_TYPE}'. Valid: github, bitbucket, gitlab, gitea"
        exit 1
        ;;
esac

ghorg "${ghorg_args[@]}"

log "Mirror clone complete."
