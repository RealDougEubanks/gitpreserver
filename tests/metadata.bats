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

@test "metadata.sh: skips non-github host types in Phase 1" {
    export GITPRESERVER_TOKEN=ghp_dummy
    export GITPRESERVER_USERNAME=alice
    export GITPRESERVER_HOST_TYPE=gitlab
    run "${REPO_ROOT}/backup/metadata.sh"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"not yet implemented"* ]]
}

@test "metadata.sh: handles empty repo list without spurious 'Found 1'" {
    # Shim gh and jq to simulate an account with zero repos.
    shim_dir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${shim_dir}"
    cat > "${shim_dir}/gh" <<'SHIM'
#!/usr/bin/env bash
# Return empty JSON array for `gh repo list ... --json name`.
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
