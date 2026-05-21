#!/usr/bin/env bats

load test_helper

# These tests shim `docker` so the wrapper's compose invocations are captured
# instead of actually run. The shim records each invocation as a line in
# ${BATS_TEST_TMPDIR}/docker-calls.

setup_docker_shim() {
    shim_dir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${shim_dir}"
    cat > "${shim_dir}/docker" <<SHIM
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${BATS_TEST_TMPDIR}/docker-calls"
exit 0
SHIM
    chmod +x "${shim_dir}/docker"
    export PATH="${shim_dir}:${PATH}"
    : > "${BATS_TEST_TMPDIR}/docker-calls"
}

@test "run-backup.sh: --help exits 0 and shows usage" {
    run "${REPO_ROOT}/run-backup.sh" --help
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Usage: run-backup.sh"* ]]
    [[ "${output}" == *"--no-sync"* ]]
}

@test "run-backup.sh: unknown option exits 2" {
    run "${REPO_ROOT}/run-backup.sh" --bogus
    [ "${status}" -eq 2 ]
    [[ "${output}" == *"unknown option"* ]]
}

@test "run-backup.sh: two positional args rejected" {
    run "${REPO_ROOT}/run-backup.sh" /tmp/a /tmp/b
    [ "${status}" -eq 2 ]
    [[ "${output}" == *"more than one destination path"* ]]
}

@test "run-backup.sh: default invocation runs mirror, metadata, sync" {
    setup_docker_shim
    # Disable flock re-exec so the shim sees the calls directly.
    export GITPRESERVER_LOCKED=1
    run "${REPO_ROOT}/run-backup.sh"
    [ "${status}" -eq 0 ]
    grep -q 'compose run --rm mirror' "${BATS_TEST_TMPDIR}/docker-calls"
    grep -q 'compose run --rm metadata' "${BATS_TEST_TMPDIR}/docker-calls"
    grep -q 'compose run --rm sync' "${BATS_TEST_TMPDIR}/docker-calls"
}

@test "run-backup.sh: --no-sync skips sync service and runs retention prune via mirror" {
    setup_docker_shim
    export GITPRESERVER_LOCKED=1
    run "${REPO_ROOT}/run-backup.sh" --no-sync
    [ "${status}" -eq 0 ]
    grep -q 'compose run --rm mirror' "${BATS_TEST_TMPDIR}/docker-calls"
    grep -q 'compose run --rm metadata' "${BATS_TEST_TMPDIR}/docker-calls"
    # The sync service itself must NOT be invoked.
    ! grep -qE 'compose run --rm( -e [^ ]+)* sync$' "${BATS_TEST_TMPDIR}/docker-calls"
    # The prune fallback uses --entrypoint sync.sh on the mirror service.
    grep -q -- '--entrypoint sync.sh mirror' "${BATS_TEST_TMPDIR}/docker-calls"
    grep -q -- '-e GITPRESERVER_RCLONE_REMOTE=' "${BATS_TEST_TMPDIR}/docker-calls"
}

@test "run-backup.sh: shell-env GITPRESERVER_DRY_RUN is honored" {
    setup_docker_shim
    export GITPRESERVER_LOCKED=1
    export GITPRESERVER_DRY_RUN=true
    run "${REPO_ROOT}/run-backup.sh"
    [ "${status}" -eq 0 ]
    while IFS= read -r line; do
        [[ -z "${line}" ]] && continue
        [[ "${line}" == *"GITPRESERVER_DRY_RUN=true"* ]] || {
            echo "Missing DRY_RUN on: ${line}" >&2
            return 1
        }
    done < "${BATS_TEST_TMPDIR}/docker-calls"
}

@test "run-backup.sh: --dry-run threads through to every stage" {
    setup_docker_shim
    export GITPRESERVER_LOCKED=1
    run "${REPO_ROOT}/run-backup.sh" --dry-run
    [ "${status}" -eq 0 ]
    # Every compose run line should carry the dry-run env override.
    while IFS= read -r line; do
        [[ -z "${line}" ]] && continue
        [[ "${line}" == *"GITPRESERVER_DRY_RUN=true"* ]] || {
            echo "Missing DRY_RUN on: ${line}" >&2
            return 1
        }
    done < "${BATS_TEST_TMPDIR}/docker-calls"
}

@test "run-backup.sh: positional DEST_PATH creates dir and exports HOST_BACKUP_DIR" {
    setup_docker_shim
    export GITPRESERVER_LOCKED=1
    dest="${BATS_TEST_TMPDIR}/custom-dest"
    [ ! -d "${dest}" ]
    run "${REPO_ROOT}/run-backup.sh" "${dest}" --no-sync
    [ "${status}" -eq 0 ]
    [ -d "${dest}" ]
    [[ "${output}" == *"Backup destination: ${dest}"* ]]
}

@test "run-backup.sh: combined flags (DEST_PATH + --no-sync + --dry-run)" {
    setup_docker_shim
    export GITPRESERVER_LOCKED=1
    dest="${BATS_TEST_TMPDIR}/combo-dest"
    run "${REPO_ROOT}/run-backup.sh" "${dest}" --no-sync --dry-run
    [ "${status}" -eq 0 ]
    [ -d "${dest}" ]
    ! grep -qE 'compose run --rm( -e [^ ]+)* sync$' "${BATS_TEST_TMPDIR}/docker-calls"
    grep -q -- '--entrypoint sync.sh mirror' "${BATS_TEST_TMPDIR}/docker-calls"
    grep -q 'GITPRESERVER_DRY_RUN=true' "${BATS_TEST_TMPDIR}/docker-calls"
}
