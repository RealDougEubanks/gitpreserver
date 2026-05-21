#!/usr/bin/env bash
set -euo pipefail

log() { printf '[gitpreserver] %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }

: "${GITPRESERVER_TOKEN:?GITPRESERVER_TOKEN is required}"
: "${GITPRESERVER_USERNAME:?GITPRESERVER_USERNAME is required}"

if ! [[ "${GITPRESERVER_USERNAME}" =~ ^[A-Za-z0-9._-]+$ ]]; then
    log "ERROR: GITPRESERVER_USERNAME contains invalid characters."
    exit 1
fi

BACKUP_DIR="${GITPRESERVER_BACKUP_DIR:-/backups}"
HOST_TYPE="${GITPRESERVER_HOST_TYPE:-github}"
DRY_RUN="${GITPRESERVER_DRY_RUN:-false}"

BACKUP_DATE=$(date -u +%Y-%m-%d)
META_DIR="${BACKUP_DIR}/${BACKUP_DATE}/metadata"

if [[ "${DRY_RUN}" == "true" ]]; then
    log "DRY RUN: would export metadata for ${GITPRESERVER_USERNAME} (${HOST_TYPE}) -> ${META_DIR}"
    exit 0
fi

if [[ "${HOST_TYPE}" != "github" ]]; then
    log "Metadata export for '${HOST_TYPE}' is not yet implemented (Phase 2). Skipping."
    exit 0
fi

mkdir -p "${META_DIR}"

# gh CLI reads GH_TOKEN from env — never logged or in argv.
export GH_TOKEN="${GITPRESERVER_TOKEN}"

log "Fetching repository list for ${GITPRESERVER_USERNAME}"

if ! repos_json=$(gh repo list "${GITPRESERVER_USERNAME}" --limit 4000 --json name 2>/dev/null); then
    log "ERROR: failed to list repositories. Verify GITPRESERVER_TOKEN has 'repo' scope."
    exit 1
fi

# Read repo names into an array so empty results and unusual names are handled correctly.
# `gh repo list --json name` with empty input emits `[]`, which jq -r outputs as nothing.
mapfile -t repos < <(printf '%s\n' "${repos_json}" | jq -r '.[].name')

repo_count=${#repos[@]}
log "Found ${repo_count} repositories. Exporting metadata..."

if (( repo_count == 0 )); then
    log "No repositories to export. Done."
    exit 0
fi

exported=0
failed=0

for repo in "${repos[@]}"; do
    # Sanity check on each repo name before using it in paths or as a CLI arg.
    if ! [[ "${repo}" =~ ^[A-Za-z0-9._-]+$ ]]; then
        log "WARNING: skipping repo with unexpected name: ${repo}"
        failed=$((failed + 1))
        continue
    fi

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

log "Metadata export complete: ${exported} repos exported, ${failed} skipped."
