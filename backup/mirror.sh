#!/usr/bin/env bash
set -euo pipefail

log() { echo "[gitpreserver] $(date +%Y-%m-%dT%H:%M:%S) $*"; }

: "${GITPRESERVER_TOKEN:?GITPRESERVER_TOKEN is required}"
: "${GITPRESERVER_USERNAME:?GITPRESERVER_USERNAME is required}"

BACKUP_DIR="${GITPRESERVER_BACKUP_DIR:-/backups}"
HOST_TYPE="${GITPRESERVER_HOST_TYPE:-github}"
HOST_URL="${GITPRESERVER_HOST_URL:-}"
DRY_RUN="${GITPRESERVER_DRY_RUN:-false}"

BACKUP_DATE=$(date +%Y-%m-%d)
OUTPUT_DIR="${BACKUP_DIR}/${BACKUP_DATE}/repos"

if [[ "${DRY_RUN}" == "true" ]]; then
    log "DRY RUN: would mirror ${GITPRESERVER_USERNAME} (${HOST_TYPE}) → ${OUTPUT_DIR}"
    exit 0
fi

mkdir -p "${OUTPUT_DIR}"

log "Starting mirror clone: ${GITPRESERVER_USERNAME} (${HOST_TYPE}) → ${OUTPUT_DIR}"

case "${HOST_TYPE}" in
    github)
        ghorg clone "${GITPRESERVER_USERNAME}" \
            --clone-type=user \
            --backup \
            --token="${GITPRESERVER_TOKEN}" \
            --output-dir="${OUTPUT_DIR}" \
            --concurrency=4
        ;;
    bitbucket)
        ghorg clone "${GITPRESERVER_USERNAME}" \
            --clone-type=user \
            --scm=bitbucket \
            --backup \
            --token="${GITPRESERVER_TOKEN}" \
            --output-dir="${OUTPUT_DIR}" \
            --concurrency=4
        ;;
    gitlab)
        GHORG_GITLAB_TOKEN="${GITPRESERVER_TOKEN}" \
        ghorg clone "${GITPRESERVER_USERNAME}" \
            --clone-type=user \
            --scm=gitlab \
            --backup \
            --output-dir="${OUTPUT_DIR}" \
            --concurrency=4 \
            ${HOST_URL:+--base-url="${HOST_URL}"}
        ;;
    gitea)
        : "${HOST_URL:?GITPRESERVER_HOST_URL is required for host type 'gitea'}"
        ghorg clone "${GITPRESERVER_USERNAME}" \
            --clone-type=user \
            --scm=gitea \
            --backup \
            --token="${GITPRESERVER_TOKEN}" \
            --output-dir="${OUTPUT_DIR}" \
            --concurrency=4 \
            --base-url="${HOST_URL}"
        ;;
    *)
        log "ERROR: unsupported GITPRESERVER_HOST_TYPE '${HOST_TYPE}'. Valid values: github, bitbucket, gitlab, gitea"
        exit 1
        ;;
esac

log "Mirror clone complete."
