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
HOST_URL="${GITPRESERVER_HOST_URL:-}"
DRY_RUN="${GITPRESERVER_DRY_RUN:-false}"

BACKUP_DATE=$(date -u +%Y-%m-%d)
META_DIR="${BACKUP_DIR}/${BACKUP_DATE}/metadata"

if [[ "${DRY_RUN}" == "true" ]]; then
    log "DRY RUN: would export metadata for ${GITPRESERVER_USERNAME} (${HOST_TYPE}) -> ${META_DIR}"
    exit 0
fi

mkdir -p "${META_DIR}"

# ---------------------------------------------------------------------------
# GitHub
# ---------------------------------------------------------------------------

export_github() {
    export GH_TOKEN="${GITPRESERVER_TOKEN}"

    log "Fetching repository list for ${GITPRESERVER_USERNAME} (GitHub)"

    if ! repos_json=$(gh repo list "${GITPRESERVER_USERNAME}" --limit 4000 --json name 2>/dev/null); then
        log "ERROR: failed to list repositories. Verify GITPRESERVER_TOKEN has 'repo' scope."
        exit 1
    fi

    mapfile -t repos < <(printf '%s\n' "${repos_json}" | jq -r '.[].name')
    repo_count=${#repos[@]}
    log "Found ${repo_count} repositories. Exporting metadata..."

    if (( repo_count == 0 )); then
        log "No repositories to export. Done."
        exit 0
    fi

    local exported=0 failed=0

    for repo in "${repos[@]}"; do
        if ! [[ "${repo}" =~ ^[A-Za-z0-9._-]+$ ]]; then
            log "WARNING: skipping repo with unexpected name: ${repo}"
            failed=$((failed + 1))
            continue
        fi

        repo_meta_dir="${META_DIR}/${repo}"
        mkdir -p "${repo_meta_dir}"
        log "  ${GITPRESERVER_USERNAME}/${repo}"

        api_base="repos/${GITPRESERVER_USERNAME}/${repo}"

        if ! gh api --paginate "${api_base}/issues?state=all&per_page=100" 2>/dev/null \
                | jq -s 'add // [] | map(select(.pull_request == null))' \
                > "${repo_meta_dir}/issues.json"; then
            echo '[]' > "${repo_meta_dir}/issues.json"
            log "  WARNING: could not export issues for ${repo}"
        fi

        if ! gh api --paginate "${api_base}/pulls?state=all&per_page=100" 2>/dev/null \
                | jq -s 'add // []' \
                > "${repo_meta_dir}/pull_requests.json"; then
            echo '[]' > "${repo_meta_dir}/pull_requests.json"
            log "  WARNING: could not export pull requests for ${repo}"
        fi

        if ! gh api --paginate "${api_base}/releases?per_page=100" 2>/dev/null \
                | jq -s 'add // []' \
                > "${repo_meta_dir}/releases.json"; then
            echo '[]' > "${repo_meta_dir}/releases.json"
            log "  WARNING: could not export releases for ${repo}"
        fi

        exported=$((exported + 1))
    done

    log "Metadata export complete: ${exported} repos exported, ${failed} skipped."
}

# ---------------------------------------------------------------------------
# Bitbucket
#
# Auth: Basic auth with username:app_password. The token is treated as the
# app password; the username is GITPRESERVER_USERNAME.
# Pagination: responses include a `next` URL in the top-level `next` key.
# Issues may not be enabled on all repos — treat 404 as empty.
# Bitbucket has no releases concept; the file is written as [].
# ---------------------------------------------------------------------------

bb_api_base="https://api.bitbucket.org/2.0"

bb_curl() {
    # Basic auth: username:token (app password).
    curl -fsSL \
        -u "${GITPRESERVER_USERNAME}:${GITPRESERVER_TOKEN}" \
        -H "Accept: application/json" \
        "$@"
}

# Fetch all pages of a Bitbucket paginated endpoint; emits raw `values` arrays
# from each page, one per line, to be merged by the caller.
bb_paginate() {
    local url="$1"
    while [[ -n "${url}" ]]; do
        local page
        page=$(bb_curl "${url}")
        printf '%s\n' "${page}" | jq -c '.values // []'
        url=$(printf '%s\n' "${page}" | jq -r '.next // empty')
    done
}

export_bitbucket() {
    log "Fetching repository list for ${GITPRESERVER_USERNAME} (Bitbucket)"

    local repos_raw
    if ! repos_raw=$(bb_paginate "${bb_api_base}/repositories/${GITPRESERVER_USERNAME}?pagelen=100" 2>/dev/null); then
        log "ERROR: failed to list Bitbucket repositories. Verify token is a valid app password with repo scope."
        exit 1
    fi

    mapfile -t repos < <(printf '%s\n' "${repos_raw}" | jq -r '.[].slug' | sort -u)
    repo_count=${#repos[@]}
    log "Found ${repo_count} repositories. Exporting metadata..."

    if (( repo_count == 0 )); then
        log "No repositories to export. Done."
        exit 0
    fi

    local exported=0 failed=0

    for repo in "${repos[@]}"; do
        if ! [[ "${repo}" =~ ^[A-Za-z0-9._-]+$ ]]; then
            log "WARNING: skipping repo with unexpected slug: ${repo}"
            failed=$((failed + 1))
            continue
        fi

        repo_meta_dir="${META_DIR}/${repo}"
        mkdir -p "${repo_meta_dir}"
        log "  ${GITPRESERVER_USERNAME}/${repo}"

        local repo_base="${bb_api_base}/repositories/${GITPRESERVER_USERNAME}/${repo}"

        # Issues — 404 when issue tracker is disabled for the repo.
        local issues_raw=""
        if issues_raw=$(bb_paginate "${repo_base}/issues?pagelen=100" 2>/dev/null); then
            printf '%s\n' "${issues_raw}" | jq -s 'add // []' > "${repo_meta_dir}/issues.json"
        else
            echo '[]' > "${repo_meta_dir}/issues.json"
        fi

        # Pull requests
        local prs_raw=""
        if prs_raw=$(bb_paginate "${repo_base}/pullrequests?state=ALL&pagelen=100" 2>/dev/null); then
            printf '%s\n' "${prs_raw}" | jq -s 'add // []' > "${repo_meta_dir}/pull_requests.json"
        else
            echo '[]' > "${repo_meta_dir}/pull_requests.json"
            log "  WARNING: could not export pull requests for ${repo}"
        fi

        # Bitbucket has no releases API; write an empty array for consistency.
        echo '[]' > "${repo_meta_dir}/releases.json"

        exported=$((exported + 1))
    done

    log "Metadata export complete: ${exported} repos exported, ${failed} skipped."
}

# ---------------------------------------------------------------------------
# GitLab
#
# Auth: PRIVATE-TOKEN header.
# Supports gitlab.com (default) and self-hosted instances via HOST_URL.
# Fetches both user-owned and group-owned projects.
# Pagination: Link header with rel="next".
# ---------------------------------------------------------------------------

export_gitlab() {
    local base_url="${HOST_URL:-https://gitlab.com}"
    # Strip trailing slash
    base_url="${base_url%/}"
    local api="${base_url}/api/v4"

    gl_curl() {
        curl -fsSL \
            -H "PRIVATE-TOKEN: ${GITPRESERVER_TOKEN}" \
            -H "Accept: application/json" \
            "$@"
    }

    # Paginate a GitLab endpoint using Link headers (rel="next").
    gl_paginate() {
        local url="${1}&per_page=100"
        while [[ -n "${url}" ]]; do
            local headers_file
            headers_file=$(mktemp)
            local body
            body=$(gl_curl -D "${headers_file}" "${url}")
            printf '%s\n' "${body}"
            # Extract rel="next" URL from Link header
            url=$(grep -i '^link:' "${headers_file}" \
                | grep -oP '<[^>]+>;\s*rel="next"' \
                | grep -oP 'https?://[^>]+' \
                || true)
            rm -f "${headers_file}"
        done
    }

    log "Fetching repository list for ${GITPRESERVER_USERNAME} (GitLab: ${base_url})"

    # Try user projects first, then group projects. Merge and deduplicate by id.
    local user_projects group_projects all_projects
    user_projects=$(gl_paginate "${api}/users/${GITPRESERVER_USERNAME}/projects?owned=true" 2>/dev/null || echo '[]')
    group_projects=$(gl_paginate "${api}/groups/${GITPRESERVER_USERNAME}/projects?include_subgroups=false" 2>/dev/null || echo '[]')

    # Merge pages: each call to gl_paginate emits one JSON array per page.
    # Collect all arrays and flatten+deduplicate by .id.
    all_projects=$(
        { printf '%s\n' "${user_projects}"; printf '%s\n' "${group_projects}"; } \
        | jq -s '[.[] | .[]] | unique_by(.id)'
    )

    mapfile -t project_ids < <(printf '%s\n' "${all_projects}" | jq -r '.[].id')
    mapfile -t project_paths < <(printf '%s\n' "${all_projects}" | jq -r '.[].path')

    repo_count=${#project_ids[@]}
    log "Found ${repo_count} projects. Exporting metadata..."

    if (( repo_count == 0 )); then
        log "No projects to export. Done."
        exit 0
    fi

    local exported=0 failed=0

    for i in "${!project_ids[@]}"; do
        local pid="${project_ids[$i]}"
        local repo="${project_paths[$i]}"

        if ! [[ "${repo}" =~ ^[A-Za-z0-9._-]+$ ]]; then
            log "WARNING: skipping project with unexpected path: ${repo}"
            failed=$((failed + 1))
            continue
        fi

        repo_meta_dir="${META_DIR}/${repo}"
        mkdir -p "${repo_meta_dir}"
        log "  ${GITPRESERVER_USERNAME}/${repo} (id=${pid})"

        local proj_api="${api}/projects/${pid}"

        local issues_raw prs_raw releases_raw
        if issues_raw=$(gl_paginate "${proj_api}/issues?state=all" 2>/dev/null); then
            printf '%s\n' "${issues_raw}" | jq -s '[.[] | .[]] | unique_by(.id)' \
                > "${repo_meta_dir}/issues.json"
        else
            echo '[]' > "${repo_meta_dir}/issues.json"
            log "  WARNING: could not export issues for ${repo}"
        fi

        if prs_raw=$(gl_paginate "${proj_api}/merge_requests?state=all" 2>/dev/null); then
            printf '%s\n' "${prs_raw}" | jq -s '[.[] | .[]] | unique_by(.id)' \
                > "${repo_meta_dir}/pull_requests.json"
        else
            echo '[]' > "${repo_meta_dir}/pull_requests.json"
            log "  WARNING: could not export merge requests for ${repo}"
        fi

        if releases_raw=$(gl_paginate "${proj_api}/releases?" 2>/dev/null); then
            printf '%s\n' "${releases_raw}" | jq -s '[.[] | .[]] | unique_by(.name)' \
                > "${repo_meta_dir}/releases.json"
        else
            echo '[]' > "${repo_meta_dir}/releases.json"
        fi

        exported=$((exported + 1))
    done

    log "Metadata export complete: ${exported} projects exported, ${failed} skipped."
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

case "${HOST_TYPE}" in
    github)    export_github    ;;
    bitbucket) export_bitbucket ;;
    gitlab)    export_gitlab    ;;
    gitea)
        log "Metadata export for 'gitea' is not yet implemented (Phase 3). Skipping."
        exit 0
        ;;
    *)
        log "ERROR: unsupported GITPRESERVER_HOST_TYPE '${HOST_TYPE}'. Valid: github, bitbucket, gitlab, gitea"
        exit 1
        ;;
esac
