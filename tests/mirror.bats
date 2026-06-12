#!/usr/bin/env bats

load test_helper

@test "mirror.sh: exits when GITPRESERVER_TOKEN is missing" {
    export GITPRESERVER_USERNAME=alice
    run "${REPO_ROOT}/backup/mirror.sh"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"GITPRESERVER_TOKEN is required"* ]]
}

@test "mirror.sh: exits when GITPRESERVER_USERNAME is missing" {
    export GITPRESERVER_TOKEN=ghp_dummy
    run "${REPO_ROOT}/backup/mirror.sh"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"GITPRESERVER_USERNAME is required"* ]]
}

@test "mirror.sh: rejects shell metacharacters in username" {
    export GITPRESERVER_TOKEN=ghp_dummy
    export GITPRESERVER_USERNAME='alice;rm -rf /'
    run "${REPO_ROOT}/backup/mirror.sh"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"invalid characters"* ]]
}

@test "mirror.sh: rejects path traversal in username" {
    export GITPRESERVER_TOKEN=ghp_dummy
    export GITPRESERVER_USERNAME='../etc'
    run "${REPO_ROOT}/backup/mirror.sh"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"invalid characters"* ]]
}

@test "mirror.sh: rejects unknown host type" {
    export GITPRESERVER_TOKEN=ghp_dummy
    export GITPRESERVER_USERNAME=alice
    export GITPRESERVER_HOST_TYPE=launchpad
    export GITPRESERVER_DRY_RUN=false
    # Place a stub ghorg in PATH so the script gets past binary lookup
    # before hitting the case branch (it won't reach ghorg, but PATH lookup
    # under `set -e` shouldn't fail either way).
    run "${REPO_ROOT}/backup/mirror.sh"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"unsupported GITPRESERVER_HOST_TYPE"* ]]
}

@test "mirror.sh: gitea host type requires GITPRESERVER_HOST_URL" {
    export GITPRESERVER_TOKEN=ghp_dummy
    export GITPRESERVER_USERNAME=alice
    export GITPRESERVER_HOST_TYPE=gitea
    run "${REPO_ROOT}/backup/mirror.sh"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"GITPRESERVER_HOST_URL"* ]]
}

@test "mirror.sh: dry-run exits 0 without invoking ghorg" {
    export GITPRESERVER_TOKEN=ghp_dummy
    export GITPRESERVER_USERNAME=alice
    export GITPRESERVER_DRY_RUN=true
    run "${REPO_ROOT}/backup/mirror.sh"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"DRY RUN"* ]]
}

@test "run-stages.sh: runs mirror -> metadata -> sync sequentially, aborting on first failure" {
    shim_dir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${shim_dir}"
    # Override the three stage scripts with shims that record invocation order.
    for stage in mirror metadata sync; do
        cat > "${shim_dir}/${stage}.sh" <<SHIM
#!/usr/bin/env bash
printf '%s\n' "${stage}" >> "${BATS_TEST_TMPDIR}/stage-order"
SHIM
        chmod +x "${shim_dir}/${stage}.sh"
    done
    export PATH="${shim_dir}:${PATH}"

    run "${REPO_ROOT}/backup/run-stages.sh"
    [ "${status}" -eq 0 ]
    [ "$(tr '\n' ' ' < "${BATS_TEST_TMPDIR}/stage-order")" = "mirror metadata sync " ]
}

@test "run-stages.sh: aborts pipeline if mirror.sh fails" {
    shim_dir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${shim_dir}"
    cat > "${shim_dir}/mirror.sh" <<'SHIM'
#!/usr/bin/env bash
exit 7
SHIM
    # If aborted correctly, metadata and sync are never invoked.
    cat > "${shim_dir}/metadata.sh" <<SHIM
#!/usr/bin/env bash
touch "${BATS_TEST_TMPDIR}/metadata-ran"
SHIM
    cat > "${shim_dir}/sync.sh" <<SHIM
#!/usr/bin/env bash
touch "${BATS_TEST_TMPDIR}/sync-ran"
SHIM
    chmod +x "${shim_dir}"/*.sh
    export PATH="${shim_dir}:${PATH}"

    run "${REPO_ROOT}/backup/run-stages.sh"
    [ "${status}" -eq 7 ]
    [ ! -e "${BATS_TEST_TMPDIR}/metadata-ran" ]
    [ ! -e "${BATS_TEST_TMPDIR}/sync-ran" ]
}

@test "mirror.sh: passes --path (absolute parent) and --output-dir=repos to ghorg" {
    # Regression guard: --output-dir is a NAME, not a path. We must use --path
    # for the absolute parent or ghorg writes to \$HOME/ghorg inside the container.
    shim_dir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${shim_dir}"
    cat > "${shim_dir}/ghorg" <<SHIM
#!/usr/bin/env bash
printf '%s\n' "\$@" > "${BATS_TEST_TMPDIR}/ghorg-args"
SHIM
    chmod +x "${shim_dir}/ghorg"
    export PATH="${shim_dir}:${PATH}"

    export GITPRESERVER_TOKEN=ghp_dummy
    export GITPRESERVER_USERNAME=alice
    run "${REPO_ROOT}/backup/mirror.sh"
    [ "${status}" -eq 0 ]
    grep -q "^--path=${GITPRESERVER_BACKUP_DIR}/" "${BATS_TEST_TMPDIR}/ghorg-args"
    grep -qx -- '--output-dir=repos' "${BATS_TEST_TMPDIR}/ghorg-args"
    # Make sure the old bug (full path passed to --output-dir) cannot regress.
    ! grep -qE '^--output-dir=.*/' "${BATS_TEST_TMPDIR}/ghorg-args"
}

@test "mirror.sh: rejects an invalid GITPRESERVER_HOST_URL" {
    shim_dir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${shim_dir}"
    cat > "${shim_dir}/ghorg" <<SHIM
#!/usr/bin/env bash
touch "${BATS_TEST_TMPDIR}/ghorg-ran"
SHIM
    chmod +x "${shim_dir}/ghorg"
    export PATH="${shim_dir}:${PATH}"

    export GITPRESERVER_TOKEN=ghp_dummy
    export GITPRESERVER_USERNAME=alice
    export GITPRESERVER_HOST_TYPE=gitea
    export GITPRESERVER_HOST_URL='https://git.example.com; rm -rf /'
    run "${REPO_ROOT}/backup/mirror.sh"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"not a valid http(s) URL"* ]]
    [ ! -e "${BATS_TEST_TMPDIR}/ghorg-ran" ]
}

@test "mirror.sh: accepts a valid GITPRESERVER_HOST_URL" {
    shim_dir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${shim_dir}"
    cat > "${shim_dir}/ghorg" <<SHIM
#!/usr/bin/env bash
printf '%s\n' "\$@" > "${BATS_TEST_TMPDIR}/ghorg-args"
SHIM
    chmod +x "${shim_dir}/ghorg"
    export PATH="${shim_dir}:${PATH}"

    export GITPRESERVER_TOKEN=ghp_dummy
    export GITPRESERVER_USERNAME=alice
    export GITPRESERVER_HOST_TYPE=gitea
    export GITPRESERVER_HOST_URL='https://git.example.com:3000'
    run "${REPO_ROOT}/backup/mirror.sh"
    [ "${status}" -eq 0 ]
    grep -qx -- '--base-url=https://git.example.com:3000' "${BATS_TEST_TMPDIR}/ghorg-args"
}

@test "mirror.sh: accepts dotted usernames like 'my.org'" {
    export GITPRESERVER_TOKEN=ghp_dummy
    export GITPRESERVER_USERNAME='my.org'
    export GITPRESERVER_DRY_RUN=true
    run "${REPO_ROOT}/backup/mirror.sh"
    [ "${status}" -eq 0 ]
}

@test "run-stages.sh: writes success status to STATUS_FILE on clean run" {
    shim_dir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${shim_dir}"
    for stage in mirror metadata sync; do
        printf '#!/usr/bin/env bash\nexit 0\n' > "${shim_dir}/${stage}.sh"
        chmod +x "${shim_dir}/${stage}.sh"
    done
    export PATH="${shim_dir}:${PATH}"
    export GITPRESERVER_STATUS_FILE="${BATS_TEST_TMPDIR}/status.json"

    run "${REPO_ROOT}/backup/run-stages.sh"
    [ "${status}" -eq 0 ]
    [ -f "${GITPRESERVER_STATUS_FILE}" ]
    result="$(jq -r '.status' "${GITPRESERVER_STATUS_FILE}")"
    [ "${result}" = "success" ]
}

@test "run-stages.sh: writes failed status to STATUS_FILE when a stage errors" {
    shim_dir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${shim_dir}"
    printf '#!/usr/bin/env bash\nexit 3\n' > "${shim_dir}/mirror.sh"
    chmod +x "${shim_dir}/mirror.sh"
    export PATH="${shim_dir}:${PATH}"
    export GITPRESERVER_STATUS_FILE="${BATS_TEST_TMPDIR}/status.json"

    run "${REPO_ROOT}/backup/run-stages.sh"
    [ "${status}" -ne 0 ]
    [ -f "${GITPRESERVER_STATUS_FILE}" ]
    result="$(jq -r '.status' "${GITPRESERVER_STATUS_FILE}")"
    [ "${result}" = "failed" ]
    msg="$(jq -r '.message' "${GITPRESERVER_STATUS_FILE}")"
    [[ "${msg}" == *"mirror"* ]]
}
