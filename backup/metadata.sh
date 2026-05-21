#!/usr/bin/env bash
set -euo pipefail

log() { echo "[gitpreserver] $(date +%Y-%m-%dT%H:%M:%S) $*"; }

: "${GITPRESERVER_TOKEN:?GITPRESERVER_TOKEN is required}"
: "${GITPRESERVER_USERNAME:?GITPRESERVER_USERNAME is required}"

BACKUP_DIR="${GITPRESERVER_BACKUP_DIR:-/backups}"
HOST_TYPE="${GITPRESERVER_HOST_TYPE:-github}"
DRY_RUN="${GITPRESERVER_DRY_RUN:-false}"

BACKUP_DATE=$(date +%Y-%m-%d)
META_DIR="${BACKUP_DIR}/${BACKUP_DATE}/metadata"

if [[ "${DRY_RUN}" == "true" ]]; then
    log "DRY RUN: would export metadata for ${GITPRESERVER_USERNAME} (${HOST_TYPE}) → ${META_DIR}"
    exit 0
fi

if [[ "${HOST_TYPE}" != "github" ]]; then
    log "Metadata export for '${HOST_TYPE}' is not yet implemented (Phase 2). Skipping."
    exit 0
fi

mkdir -p "${META_DIR}"

export GH_TOKEN="${GITPRESERVER_TOKEN}"

log "Fetching repository list for ${GITPRESERVER_USERNAME}"

repos=$(gh repo list "${GITPRESERVER_USERNAME}" \
    --limit 1000 \
    --json name \
    --jq '.[].name') || {
    log "ERROR: failed to list repositories. Check that GITPRESERVER_TOKEN has 'repo' scope."
    exit 1
}

repo_count=$(echo "${repos}" | wc -l | tr -d ' ')
log "Found ${repo_count} repositories. Exporting metadata..."

exported=0
failed=0

for repo in ${repos}; do
    repo_meta_dir="${META_DIR}/${repo}"
    mkdir -p "${repo_meta_dir}"

    log "  ${GITPRESERVER_USERNAME}/${repo}"

    if ! gh issue list \
            --repo "${GITPRESERVER_USERNAME}/${repo}" \
            --state all \
            --limit 10000 \
            --json number,title,state,body,labels,assignees,createdAt,closedAt,author \
            > "${repo_meta_dir}/issues.json" 2>/dev/null; then
        echo '[]' > "${repo_meta_dir}/issues.json"
        log "  WARNING: could not export issues for ${repo}"
    fi

    if ! gh pr list \
            --repo "${GITPRESERVER_USERNAME}/${repo}" \
            --state all \
            --limit 10000 \
            --json number,title,state,body,labels,assignees,createdAt,closedAt,author,mergedAt \
            > "${repo_meta_dir}/pull_requests.json" 2>/dev/null; then
        echo '[]' > "${repo_meta_dir}/pull_requests.json"
        log "  WARNING: could not export pull requests for ${repo}"
    fi

    if ! gh release list \
            --repo "${GITPRESERVER_USERNAME}/${repo}" \
            --limit 1000 \
            --json name,tagName,publishedAt,isDraft,isPrerelease,body \
            > "${repo_meta_dir}/releases.json" 2>/dev/null; then
        echo '[]' > "${repo_meta_dir}/releases.json"
        log "  WARNING: could not export releases for ${repo}"
    fi

    exported=$((exported + 1))
done

log "Metadata export complete: ${exported} repos exported, ${failed} failed."
