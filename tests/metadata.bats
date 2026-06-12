#!/usr/bin/env bats

load test_helper

@test "metadata.sh: exits when GITPRESERVER_TOKEN is missing" {
    export GITPRESERVER_USERNAME=alice
    run "${REPO_ROOT}/backup/metadata.sh"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"GITPRESERVER_TOKEN is required"* ]]
}

@test "metadata.sh: exits when GITPRESERVER_USERNAME is missing" {
    export GITPRESERVER_TOKEN=ghp_dummy
    run "${REPO_ROOT}/backup/metadata.sh"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"GITPRESERVER_USERNAME is required"* ]]
}

@test "metadata.sh: rejects invalid username" {
    export GITPRESERVER_TOKEN=ghp_dummy
    export GITPRESERVER_USERNAME='alice;rm -rf /'
    run "${REPO_ROOT}/backup/metadata.sh"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"invalid characters"* ]]
}

@test "metadata.sh: dry-run exits 0 without invoking gh" {
    export GITPRESERVER_TOKEN=ghp_dummy
    export GITPRESERVER_USERNAME=alice
    export GITPRESERVER_DRY_RUN=true
    run "${REPO_ROOT}/backup/metadata.sh"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"DRY RUN"* ]]
}

@test "metadata.sh: rejects unknown host type" {
    export GITPRESERVER_TOKEN=token
    export GITPRESERVER_USERNAME=alice
    export GITPRESERVER_HOST_TYPE=unknown
    run "${REPO_ROOT}/backup/metadata.sh"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"unsupported GITPRESERVER_HOST_TYPE"* ]]
}

@test "metadata.sh: gitea skips with 'not yet implemented'" {
    export GITPRESERVER_TOKEN=token
    export GITPRESERVER_USERNAME=alice
    export GITPRESERVER_HOST_TYPE=gitea
    run "${REPO_ROOT}/backup/metadata.sh"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"not yet implemented"* ]]
}

@test "metadata.sh: github — handles empty repo list" {
    shim_dir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${shim_dir}"
    cat > "${shim_dir}/gh" <<'SHIM'
#!/usr/bin/env bash
printf '[]'
SHIM
    chmod +x "${shim_dir}/gh"
    export PATH="${shim_dir}:${PATH}"

    export GITPRESERVER_TOKEN=ghp_dummy
    export GITPRESERVER_USERNAME=alice
    run "${REPO_ROOT}/backup/metadata.sh"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Found 0 repositories"* ]]
    [[ "${output}" == *"No repositories to export"* ]]
}

@test "metadata.sh: github — exports issues, pull_requests, releases for each repo" {
    shim_dir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${shim_dir}"

    # gh repo list returns one repo named "myrepo"
    cat > "${shim_dir}/gh" <<'SHIM'
#!/usr/bin/env bash
case "$*" in
    *"repo list"*) printf '[{"name":"myrepo"}]' ;;
    *) printf '[]' ;;
esac
SHIM
    chmod +x "${shim_dir}/gh"
    export PATH="${shim_dir}:${PATH}"

    export GITPRESERVER_TOKEN=ghp_dummy
    export GITPRESERVER_USERNAME=alice
    run "${REPO_ROOT}/backup/metadata.sh"
    [ "${status}" -eq 0 ]
    [ -f "${GITPRESERVER_BACKUP_DIR}/$(date -u +%Y-%m-%d)/metadata/myrepo/issues.json" ]
    [ -f "${GITPRESERVER_BACKUP_DIR}/$(date -u +%Y-%m-%d)/metadata/myrepo/pull_requests.json" ]
    [ -f "${GITPRESERVER_BACKUP_DIR}/$(date -u +%Y-%m-%d)/metadata/myrepo/releases.json" ]
}

@test "metadata.sh: bitbucket — handles empty repo list" {
    shim_dir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${shim_dir}"

    # Stub curl to return a Bitbucket-shaped empty page response
    cat > "${shim_dir}/curl" <<'SHIM'
#!/usr/bin/env bash
printf '{"values":[]}'
SHIM
    chmod +x "${shim_dir}/curl"
    export PATH="${shim_dir}:${PATH}"

    export GITPRESERVER_TOKEN=app_password
    export GITPRESERVER_USERNAME=alice
    export GITPRESERVER_HOST_TYPE=bitbucket
    run "${REPO_ROOT}/backup/metadata.sh"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Found 0 repositories"* ]]
}

@test "metadata.sh: bitbucket — exports metadata files for each repo" {
    shim_dir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${shim_dir}"

    # First call = repo list; subsequent calls = issues/PRs (return empty values)
    call_count=0
    cat > "${shim_dir}/curl" <<'SHIM'
#!/usr/bin/env bash
# Detect which endpoint is being called from the URL argument
for arg in "$@"; do
    if [[ "${arg}" == */repositories/alice* && "${arg}" != */issues* && "${arg}" != */pullrequests* ]]; then
        printf '{"values":[{"slug":"repo1"}]}'
        exit 0
    fi
done
printf '{"values":[]}'
SHIM
    chmod +x "${shim_dir}/curl"
    export PATH="${shim_dir}:${PATH}"

    export GITPRESERVER_TOKEN=app_password
    export GITPRESERVER_USERNAME=alice
    export GITPRESERVER_HOST_TYPE=bitbucket
    run "${REPO_ROOT}/backup/metadata.sh"
    [ "${status}" -eq 0 ]
    [ -f "${GITPRESERVER_BACKUP_DIR}/$(date -u +%Y-%m-%d)/metadata/repo1/issues.json" ]
    [ -f "${GITPRESERVER_BACKUP_DIR}/$(date -u +%Y-%m-%d)/metadata/repo1/pull_requests.json" ]
    [ -f "${GITPRESERVER_BACKUP_DIR}/$(date -u +%Y-%m-%d)/metadata/repo1/releases.json" ]
}

@test "metadata.sh: bitbucket — curl is not invoked with -u user:token on the command line" {
    shim_dir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${shim_dir}"

    # Record every curl argv to a log, then behave like an empty repo list so
    # the run exits cleanly. The assertion below checks the recorded argv.
    arg_log="${BATS_TEST_TMPDIR}/curl-args.log"
    export ARG_LOG="${arg_log}"
    cat > "${shim_dir}/curl" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${ARG_LOG}"
printf '{"values":[]}'
SHIM
    chmod +x "${shim_dir}/curl"
    export PATH="${shim_dir}:${PATH}"

    export GITPRESERVER_TOKEN=app_password
    export GITPRESERVER_USERNAME=alice
    export GITPRESERVER_HOST_TYPE=bitbucket
    run "${REPO_ROOT}/backup/metadata.sh"
    [ "${status}" -eq 0 ]

    # The secret must never appear on the command line — no -u and no token.
    run cat "${arg_log}"
    [[ "${output}" != *"-u "* ]]
    [[ "${output}" != *"app_password"* ]]
    [[ "${output}" != *"alice:app_password"* ]]
    # Auth must instead be supplied via a curl config file.
    [[ "${output}" == *"--config"* ]]
}

@test "metadata.sh: bitbucket — --max-time present in curl args" {
    shim_dir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${shim_dir}"

    arg_log="${BATS_TEST_TMPDIR}/curl-args.log"
    export ARG_LOG="${arg_log}"
    cat > "${shim_dir}/curl" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${ARG_LOG}"
printf '{"values":[]}'
SHIM
    chmod +x "${shim_dir}/curl"
    export PATH="${shim_dir}:${PATH}"

    export GITPRESERVER_TOKEN=app_password
    export GITPRESERVER_USERNAME=alice
    export GITPRESERVER_HOST_TYPE=bitbucket
    run "${REPO_ROOT}/backup/metadata.sh"
    [ "${status}" -eq 0 ]

    run cat "${arg_log}"
    [[ "${output}" == *"--max-time"* ]]
}

@test "metadata.sh: bitbucket — curl failure on page 2 writes no complete JSON and exits non-zero" {
    shim_dir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${shim_dir}"

    # Repo list returns one repo. The issues endpoint paginates: page 1 has a
    # `next`, but the second fetch (page 2) fails with a transient error
    # (curl exit 7 = connection failure), simulating mid-pagination failure.
    counter="${BATS_TEST_TMPDIR}/issues-page-count"
    : > "${counter}"
    export COUNTER="${counter}"
    cat > "${shim_dir}/curl" <<'SHIM'
#!/usr/bin/env bash
url=""
for arg in "$@"; do
    case "${arg}" in
        http*) url="${arg}" ;;
    esac
done

# Repo listing call.
if [[ "${url}" == */repositories/alice* && "${url}" != */issues* && "${url}" != */pullrequests* ]]; then
    printf '{"values":[{"slug":"repo1"}]}'
    exit 0
fi

# Issues pagination: first page returns a `next`, second page fails hard.
if [[ "${url}" == */issues* ]]; then
    n=$(($(cat "${COUNTER}" 2>/dev/null || echo 0) + 1))
    printf '%s' "${n}" > "${COUNTER}"
    if [[ "${n}" -eq 1 ]]; then
        printf '{"values":[{"id":1}],"next":"https://api.bitbucket.org/2.0/repositories/alice/repo1/issues?page=2"}'
        exit 0
    fi
    # Page 2: simulate a connection failure.
    exit 7
fi

# Pull requests and anything else: empty.
printf '{"values":[]}'
SHIM
    chmod +x "${shim_dir}/curl"
    export PATH="${shim_dir}:${PATH}"

    export GITPRESERVER_TOKEN=app_password
    export GITPRESERVER_USERNAME=alice
    export GITPRESERVER_HOST_TYPE=bitbucket
    run "${REPO_ROOT}/backup/metadata.sh"

    # The stage must propagate a non-zero exit for the failed repo.
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"ERROR"* ]]

    meta="${GITPRESERVER_BACKUP_DIR}/$(date -u +%Y-%m-%d)/metadata/repo1"
    # No complete issues.json must exist — only a .partial marker.
    [ ! -f "${meta}/issues.json" ]
    [ -f "${meta}/issues.json.partial" ]
}

@test "metadata.sh: gitlab — rejects invalid HOST_URL" {
    export GITPRESERVER_TOKEN=glpat_dummy
    export GITPRESERVER_USERNAME=alice
    export GITPRESERVER_HOST_TYPE=gitlab
    export GITPRESERVER_HOST_URL='not a url; rm -rf /'
    run "${REPO_ROOT}/backup/metadata.sh"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"not a valid http(s) URL"* ]]
}

@test "metadata.sh: gitlab — --max-time present in curl args" {
    shim_dir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${shim_dir}"

    arg_log="${BATS_TEST_TMPDIR}/curl-args.log"
    export ARG_LOG="${arg_log}"
    cat > "${shim_dir}/curl" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${ARG_LOG}"
args=("$@")
i=0
while (( i < ${#args[@]} )); do
    if [[ "${args[$i]}" == "-D" ]]; then
        i=$(( i + 1 ))
        printf '' > "${args[$i]}"
    fi
    i=$(( i + 1 ))
done
printf '[]'
SHIM
    chmod +x "${shim_dir}/curl"
    export PATH="${shim_dir}:${PATH}"

    export GITPRESERVER_TOKEN=glpat_dummy
    export GITPRESERVER_USERNAME=alice
    export GITPRESERVER_HOST_TYPE=gitlab
    run "${REPO_ROOT}/backup/metadata.sh"
    [ "${status}" -eq 0 ]

    run cat "${arg_log}"
    [[ "${output}" == *"--max-time"* ]]
}

@test "metadata.sh: gitlab — handles empty project list" {
    shim_dir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${shim_dir}"

    # Stub curl: return empty array for all GitLab API calls.
    # Parse -D <file> to write an empty header file so gl_paginate's Link
    # extraction produces no "next" URL and the loop terminates.
    cat > "${shim_dir}/curl" <<'SHIM'
#!/usr/bin/env bash
args=("$@")
i=0
while (( i < ${#args[@]} )); do
    if [[ "${args[$i]}" == "-D" ]]; then
        i=$(( i + 1 ))
        printf '' > "${args[$i]}"
    fi
    i=$(( i + 1 ))
done
printf '[]'
SHIM
    chmod +x "${shim_dir}/curl"
    export PATH="${shim_dir}:${PATH}"

    export GITPRESERVER_TOKEN=glpat_dummy
    export GITPRESERVER_USERNAME=alice
    export GITPRESERVER_HOST_TYPE=gitlab
    run "${REPO_ROOT}/backup/metadata.sh"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Found 0 projects"* ]]
}
