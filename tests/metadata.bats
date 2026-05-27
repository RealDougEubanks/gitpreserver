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
