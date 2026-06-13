#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"

: "${GITPRESERVER_TOKEN:?GITPRESERVER_TOKEN is required}"
: "${GITPRESERVER_USERNAME:?GITPRESERVER_USERNAME is required}"

# Validate username — accept only characters the four supported hosts allow.
# Refuses shell metacharacters and path separators before they ever reach ghorg.
if ! [[ "${GITPRESERVER_USERNAME}" =~ ^[A-Za-z0-9._-]+$ ]]; then
    log_error "ERROR: GITPRESERVER_USERNAME contains invalid characters."
    exit 1
fi

# Validate a self-hosted base URL before it reaches ghorg --base-url.
# GITPRESERVER_HOST_URL is operator-supplied but untrusted; require an
# http(s) scheme followed by a hostname (optionally port and path) and
# reject anything containing shell metacharacters or whitespace.
validate_host_url() {
    local url="$1"
    [[ "${url}" =~ ^https?://[A-Za-z0-9._-]+(:[0-9]+)?(/[A-Za-z0-9._~/-]*)?$ ]]
}

BACKUP_DIR="${GITPRESERVER_BACKUP_DIR:-/backups}"
HOST_TYPE="${GITPRESERVER_HOST_TYPE:-github}"
HOST_URL="${GITPRESERVER_HOST_URL:-}"
DRY_RUN="${GITPRESERVER_DRY_RUN:-false}"
CONCURRENCY="${GITPRESERVER_CONCURRENCY:-4}"

BACKUP_DATE=$(date -u +%Y-%m-%d)
SNAPSHOT_PARENT="${BACKUP_DIR}/${BACKUP_DATE}"
OUTPUT_DIR="${SNAPSHOT_PARENT}/repos"

if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "DRY RUN: would mirror ${GITPRESERVER_USERNAME} (${HOST_TYPE}) -> ${OUTPUT_DIR}"
    exit 0
fi

mkdir -p "${SNAPSHOT_PARENT}"

# Trust the backup repos for git operations. They live on a bind-mounted volume
# and, on a re-run into an existing snapshot, git inside the container may see
# them as owned by a different user and refuse with "detected dubious ownership"
# (exit 128) — which ghorg surfaces as "Problem setting remote with credentials".
# git's safe.directory matches exact repo paths or the special '*'; there is no
# recursive directory glob, and the per-repo paths vary, so '*' is the only way
# to cover them. This is the gitpreserver user's own data in a single-tenant
# container, so trusting all repos is appropriate.
git config --global --add safe.directory '*' 2>/dev/null || true

log_info "Starting mirror clone: ${GITPRESERVER_USERNAME} (${HOST_TYPE}) -> ${OUTPUT_DIR}"

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
            if ! validate_host_url "${HOST_URL}"; then
                log_error "ERROR: GITPRESERVER_HOST_URL is not a valid http(s) URL: '${HOST_URL}'"
                exit 1
            fi
            ghorg_args+=(--base-url="${HOST_URL}")
        fi
        ;;
    gitea)
        : "${HOST_URL:?GITPRESERVER_HOST_URL is required for host type 'gitea'}"
        if ! validate_host_url "${HOST_URL}"; then
            log_error "ERROR: GITPRESERVER_HOST_URL is not a valid http(s) URL: '${HOST_URL}'"
            exit 1
        fi
        export GHORG_GITEA_TOKEN="${GITPRESERVER_TOKEN}"
        ghorg_args+=(--scm=gitea --base-url="${HOST_URL}")
        ;;
    *)
        log_error "ERROR: unsupported GITPRESERVER_HOST_TYPE '${HOST_TYPE}'. Valid: github, bitbucket, gitlab, gitea"
        exit 1
        ;;
esac

ghorg "${ghorg_args[@]}"

log_info "Mirror clone complete."
