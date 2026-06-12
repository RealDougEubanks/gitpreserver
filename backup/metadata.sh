#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"

# HTTP request timeout (seconds) applied to every curl call. Kept consistent
# across Bitbucket and GitLab so a hung upstream can never wedge a backup.
HTTP_MAX_TIME=30
# Timeout (seconds) wrapping each `gh` invocation for parity with curl.
GH_TIMEOUT=60

# Resolve a timeout command (GNU coreutils `timeout`, or `gtimeout` on macOS).
# Empty when neither is present so the call still runs, just unbounded.
GH_TIMEOUT_CMD=()
if command -v timeout >/dev/null 2>&1; then
    GH_TIMEOUT_CMD=(timeout "${GH_TIMEOUT}")
elif command -v gtimeout >/dev/null 2>&1; then
    GH_TIMEOUT_CMD=(gtimeout "${GH_TIMEOUT}")
fi

# Run `gh` bounded by the timeout command when one is available. The
# ${arr[@]+...} guard keeps this safe under `set -u` with an empty array
# (bash 3.2 on macOS errors on a bare empty-array expansion).
gh_t() {
    if (( ${#GH_TIMEOUT_CMD[@]} > 0 )); then
        "${GH_TIMEOUT_CMD[@]}" gh "$@"
    else
        gh "$@"
    fi
}

STATUS_FILE="${GITPRESERVER_STATUS_FILE:-/tmp/gitpreserver-status.json}"

# Append a status record matching run-stages.sh's schema. Best-effort: a
# failure to write status must never abort the backup itself.
write_status() {
    local status="$1" message="$2"
    command -v jq >/dev/null 2>&1 || return 0
    jq -cn \
        --arg s "${status}" \
        --arg m "${message}" \
        --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{status:$s, last_run:$t, message:$m}' \
        > "${STATUS_FILE}" 2>/dev/null || true
}

: "${GITPRESERVER_TOKEN:?GITPRESERVER_TOKEN is required}"
: "${GITPRESERVER_USERNAME:?GITPRESERVER_USERNAME is required}"

if ! [[ "${GITPRESERVER_USERNAME}" =~ ^[A-Za-z0-9._-]+$ ]]; then
    log_error "ERROR: GITPRESERVER_USERNAME contains invalid characters."
    exit 1
fi

BACKUP_DIR="${GITPRESERVER_BACKUP_DIR:-/backups}"
HOST_TYPE="${GITPRESERVER_HOST_TYPE:-github}"
HOST_URL="${GITPRESERVER_HOST_URL:-}"
DRY_RUN="${GITPRESERVER_DRY_RUN:-false}"

BACKUP_DATE=$(date -u +%Y-%m-%d)
META_DIR="${BACKUP_DIR}/${BACKUP_DATE}/metadata"

if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "DRY RUN: would export metadata for ${GITPRESERVER_USERNAME} (${HOST_TYPE}) -> ${META_DIR}"
    exit 0
fi

mkdir -p "${META_DIR}"

# ---------------------------------------------------------------------------
# GitHub
# ---------------------------------------------------------------------------

export_github() {
    export GH_TOKEN="${GITPRESERVER_TOKEN}"

    log_info "Fetching repository list for ${GITPRESERVER_USERNAME} (GitHub)"

    if ! repos_json=$(gh_t repo list "${GITPRESERVER_USERNAME}" --limit 4000 --json name 2>/dev/null); then
        log_error "ERROR: failed to list repositories. Verify GITPRESERVER_TOKEN has 'repo' scope."
        exit 1
    fi

    mapfile -t repos < <(printf '%s\n' "${repos_json}" | jq -r '.[].name')
    repo_count=${#repos[@]}
    log_info "Found ${repo_count} repositories. Exporting metadata..."

    if (( repo_count == 0 )); then
        log_info "No repositories to export. Done."
        exit 0
    fi

    local exported=0 failed=0

    for repo in "${repos[@]}"; do
        if ! [[ "${repo}" =~ ^[A-Za-z0-9._-]+$ ]]; then
            log_warn "WARNING: skipping repo with unexpected name: ${repo}"
            failed=$((failed + 1))
            continue
        fi

        repo_meta_dir="${META_DIR}/${repo}"
        mkdir -p "${repo_meta_dir}"
        log_info "  ${GITPRESERVER_USERNAME}/${repo}"

        api_base="repos/${GITPRESERVER_USERNAME}/${repo}"

        if ! gh_t api --paginate "${api_base}/issues?state=all&per_page=100" 2>/dev/null \
                | jq -s 'add // [] | map(select(.pull_request == null))' \
                > "${repo_meta_dir}/issues.json"; then
            echo '[]' > "${repo_meta_dir}/issues.json"
            log_warn "  WARNING: could not export issues for ${repo}"
        fi

        if ! gh_t api --paginate "${api_base}/pulls?state=all&per_page=100" 2>/dev/null \
                | jq -s 'add // []' \
                > "${repo_meta_dir}/pull_requests.json"; then
            echo '[]' > "${repo_meta_dir}/pull_requests.json"
            log_warn "  WARNING: could not export pull requests for ${repo}"
        fi

        if ! gh_t api --paginate "${api_base}/releases?per_page=100" 2>/dev/null \
                | jq -s 'add // []' \
                > "${repo_meta_dir}/releases.json"; then
            echo '[]' > "${repo_meta_dir}/releases.json"
            log_warn "  WARNING: could not export releases for ${repo}"
        fi

        exported=$((exported + 1))
    done

    log_info "Metadata export complete: ${exported} repos exported, ${failed} skipped."
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

# Credential config file consumed by `curl --config`. Holding the
# username:app-password here keeps it out of /proc/<pid>/cmdline and `ps`
# (unlike `-u user:pass`). Created lazily and shredded on EXIT — see
# mirror.sh:39-40 for the equivalent intent on the ghorg side.
BB_CURL_CONFIG=""

cleanup_bb_config() {
    if [[ -n "${BB_CURL_CONFIG}" && -f "${BB_CURL_CONFIG}" ]]; then
        rm -f "${BB_CURL_CONFIG}"
    fi
}
trap 'cleanup_bb_config' EXIT

bb_write_curl_config() {
    BB_CURL_CONFIG=$(mktemp)
    chmod 0600 "${BB_CURL_CONFIG}"
    # curl --config parses key = "value"; the leading user line supplies
    # HTTP Basic auth without exposing the secret on the command line.
    printf 'user = "%s:%s"\n' "${GITPRESERVER_USERNAME}" "${GITPRESERVER_TOKEN}" \
        > "${BB_CURL_CONFIG}"
}

bb_curl() {
    # Auth (username:app password) is read from the 0600 config file, never
    # the argv. --max-time bounds each request so a hung upstream can't wedge.
    curl -fsSL \
        --config "${BB_CURL_CONFIG}" \
        --max-time "${HTTP_MAX_TIME}" \
        -H "Accept: application/json" \
        "$@"
}

# Fetch all pages of a Bitbucket paginated endpoint; emits raw `values` arrays
# from each page, one per line, to be merged by the caller. Returns non-zero
# (and logs context) if any page fails so callers never persist a truncated
# result set as if it were complete.
bb_paginate() {
    local url="$1"
    local context="${2:-${url}}"
    local page rc page_no=0
    while [[ -n "${url}" ]]; do
        page_no=$((page_no + 1))
        rc=0
        page=$(bb_curl "${url}") || rc=$?
        if (( rc != 0 )); then
            log_error "  ERROR: Bitbucket request failed (host=api.bitbucket.org repo=${context} endpoint=${url} page=${page_no} curl_exit=${rc})"
            return "${rc}"
        fi
        printf '%s\n' "${page}" | jq -c '.values // []'
        url=$(printf '%s\n' "${page}" | jq -r '.next // empty')
    done
}

export_bitbucket() {
    log_info "Fetching repository list for ${GITPRESERVER_USERNAME} (Bitbucket)"

    bb_write_curl_config

    local repos_raw
    if ! repos_raw=$(bb_paginate "${bb_api_base}/repositories/${GITPRESERVER_USERNAME}?pagelen=100" "${GITPRESERVER_USERNAME}"); then
        log_error "ERROR: failed to list Bitbucket repositories. Verify token is a valid app password with repo scope."
        exit 1
    fi

    mapfile -t repos < <(printf '%s\n' "${repos_raw}" | jq -r '.[].slug' | sort -u)
    repo_count=${#repos[@]}
    log_info "Found ${repo_count} repositories. Exporting metadata..."

    if (( repo_count == 0 )); then
        log_info "No repositories to export. Done."
        exit 0
    fi

    local exported=0 failed=0

    for repo in "${repos[@]}"; do
        if ! [[ "${repo}" =~ ^[A-Za-z0-9._-]+$ ]]; then
            log_warn "WARNING: skipping repo with unexpected slug: ${repo}"
            failed=$((failed + 1))
            continue
        fi

        repo_meta_dir="${META_DIR}/${repo}"
        mkdir -p "${repo_meta_dir}"
        log_info "  ${GITPRESERVER_USERNAME}/${repo}"

        local repo_base="${bb_api_base}/repositories/${GITPRESERVER_USERNAME}/${repo}"
        local repo_failed=0

        # Issues — curl exit 22 means an HTTP 4xx (commonly 404 when the issue
        # tracker is disabled). Treat that as "no issues" (empty). Any other
        # failure (network/timeout/5xx) is a real error: write a .partial file
        # so the truncated set is never mistaken for a complete export.
        local issues_raw="" rc=0
        issues_raw=$(bb_paginate "${repo_base}/issues?pagelen=100" "${repo}") || rc=$?
        if (( rc == 0 )); then
            printf '%s\n' "${issues_raw}" | jq -s 'add // []' > "${repo_meta_dir}/issues.json"
        elif (( rc == 22 )); then
            echo '[]' > "${repo_meta_dir}/issues.json"
        else
            printf '%s\n' "${issues_raw}" | jq -s 'add // []' > "${repo_meta_dir}/issues.json.partial" 2>/dev/null || true
            log_error "  ERROR: incomplete issues for ${repo}; wrote issues.json.partial (curl_exit=${rc})"
            repo_failed=1
        fi

        # Pull requests
        local prs_raw=""
        rc=0
        prs_raw=$(bb_paginate "${repo_base}/pullrequests?state=ALL&pagelen=100" "${repo}") || rc=$?
        if (( rc == 0 )); then
            printf '%s\n' "${prs_raw}" | jq -s 'add // []' > "${repo_meta_dir}/pull_requests.json"
        else
            printf '%s\n' "${prs_raw}" | jq -s 'add // []' > "${repo_meta_dir}/pull_requests.json.partial" 2>/dev/null || true
            log_error "  ERROR: incomplete pull requests for ${repo}; wrote pull_requests.json.partial (curl_exit=${rc})"
            repo_failed=1
        fi

        # Bitbucket has no releases API; write an empty array for consistency.
        echo '[]' > "${repo_meta_dir}/releases.json"

        if (( repo_failed != 0 )); then
            failed=$((failed + 1))
        else
            exported=$((exported + 1))
        fi
    done

    log_info "Metadata export complete: ${exported} repos exported, ${failed} failed/skipped."

    if (( failed != 0 )); then
        log_error "ERROR: ${failed} Bitbucket repo(s) had incomplete metadata."
        return 1
    fi
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
    # Validate the host URL before it reaches curl: it must be an http(s) URL
    # with a plausible hostname. Rejecting malformed values here prevents
    # SSRF-style surprises and confusing curl errors.
    if ! [[ "${base_url}" =~ ^https?://[A-Za-z0-9._~-]+(:[0-9]+)?(/[A-Za-z0-9._~/%-]*)?$ ]]; then
        log_error "ERROR: GITPRESERVER_HOST_URL '${base_url}' is not a valid http(s) URL."
        exit 1
    fi
    # Strip trailing slash
    base_url="${base_url%/}"
    local api="${base_url}/api/v4"

    gl_curl() {
        curl -fsSL \
            --max-time "${HTTP_MAX_TIME}" \
            -H "PRIVATE-TOKEN: ${GITPRESERVER_TOKEN}" \
            -H "Accept: application/json" \
            "$@"
    }

    # Paginate a GitLab endpoint using Link headers (rel="next"). Returns
    # non-zero (logging context) on the first failed page so callers never
    # persist a truncated set as a complete export.
    gl_paginate() {
        local url="${1}&per_page=100"
        local context="${2:-${url}}"
        local headers_file body rc page_no=0
        while [[ -n "${url}" ]]; do
            page_no=$((page_no + 1))
            headers_file=$(mktemp)
            rc=0
            body=$(gl_curl -D "${headers_file}" "${url}") || rc=$?
            if (( rc != 0 )); then
                rm -f "${headers_file}"
                log_error "  ERROR: GitLab request failed (host=${base_url} repo=${context} endpoint=${url} page=${page_no} curl_exit=${rc})"
                return "${rc}"
            fi
            printf '%s\n' "${body}"
            # Extract rel="next" URL from Link header
            url=$(grep -i '^link:' "${headers_file}" \
                | grep -oP '<[^>]+>;\s*rel="next"' \
                | grep -oP 'https?://[^>]+' \
                || true)
            rm -f "${headers_file}"
        done
    }

    log_info "Fetching repository list for ${GITPRESERVER_USERNAME} (GitLab: ${base_url})"

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
    log_info "Found ${repo_count} projects. Exporting metadata..."

    if (( repo_count == 0 )); then
        log_info "No projects to export. Done."
        exit 0
    fi

    local exported=0 failed=0

    for i in "${!project_ids[@]}"; do
        local pid="${project_ids[$i]}"
        local repo="${project_paths[$i]}"

        if ! [[ "${repo}" =~ ^[A-Za-z0-9._-]+$ ]]; then
            log_warn "WARNING: skipping project with unexpected path: ${repo}"
            failed=$((failed + 1))
            continue
        fi

        repo_meta_dir="${META_DIR}/${repo}"
        mkdir -p "${repo_meta_dir}"
        log_info "  ${GITPRESERVER_USERNAME}/${repo} (id=${pid})"

        local proj_api="${api}/projects/${pid}"
        local repo_failed=0

        local issues_raw prs_raw releases_raw rc=0
        issues_raw=$(gl_paginate "${proj_api}/issues?state=all" "${repo}") || rc=$?
        if (( rc == 0 )); then
            printf '%s\n' "${issues_raw}" | jq -s '[.[] | .[]] | unique_by(.id)' \
                > "${repo_meta_dir}/issues.json"
        else
            printf '%s\n' "${issues_raw}" | jq -s '[.[] | .[]] | unique_by(.id)' \
                > "${repo_meta_dir}/issues.json.partial" 2>/dev/null || true
            log_error "  ERROR: incomplete issues for ${repo}; wrote issues.json.partial (curl_exit=${rc})"
            repo_failed=1
        fi

        rc=0
        prs_raw=$(gl_paginate "${proj_api}/merge_requests?state=all" "${repo}") || rc=$?
        if (( rc == 0 )); then
            printf '%s\n' "${prs_raw}" | jq -s '[.[] | .[]] | unique_by(.id)' \
                > "${repo_meta_dir}/pull_requests.json"
        else
            printf '%s\n' "${prs_raw}" | jq -s '[.[] | .[]] | unique_by(.id)' \
                > "${repo_meta_dir}/pull_requests.json.partial" 2>/dev/null || true
            log_error "  ERROR: incomplete merge requests for ${repo}; wrote pull_requests.json.partial (curl_exit=${rc})"
            repo_failed=1
        fi

        rc=0
        releases_raw=$(gl_paginate "${proj_api}/releases?" "${repo}") || rc=$?
        if (( rc == 0 )); then
            printf '%s\n' "${releases_raw}" | jq -s '[.[] | .[]] | unique_by(.name)' \
                > "${repo_meta_dir}/releases.json"
        else
            printf '%s\n' "${releases_raw}" | jq -s '[.[] | .[]] | unique_by(.name)' \
                > "${repo_meta_dir}/releases.json.partial" 2>/dev/null || true
            log_error "  ERROR: incomplete releases for ${repo}; wrote releases.json.partial (curl_exit=${rc})"
            repo_failed=1
        fi

        if (( repo_failed != 0 )); then
            failed=$((failed + 1))
        else
            exported=$((exported + 1))
        fi
    done

    log_info "Metadata export complete: ${exported} projects exported, ${failed} failed/skipped."

    if (( failed != 0 )); then
        log_error "ERROR: ${failed} GitLab project(s) had incomplete metadata."
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

case "${HOST_TYPE}" in
    github)    export_github    ;;
    bitbucket) export_bitbucket ;;
    gitlab)    export_gitlab    ;;
    gitea)
        msg="Metadata export for 'gitea' is not yet implemented (Phase 3). No issues/PRs/releases were exported."
        log_warn "WARNING: ${msg} Skipping."
        # Surface the skip so a successful-looking run is not mistaken for a
        # complete one. notify.sh / the webserver read this status file.
        write_status "warning" "${msg}"
        exit 0
        ;;
    *)
        log_error "ERROR: unsupported GITPRESERVER_HOST_TYPE '${HOST_TYPE}'. Valid: github, bitbucket, gitlab, gitea"
        exit 1
        ;;
esac
