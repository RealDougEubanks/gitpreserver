#!/usr/bin/env bats

load test_helper

@test "sync.sh: rejects non-numeric GITPRESERVER_RETENTION_DAYS" {
    export GITPRESERVER_RETENTION_DAYS='thirty; rm -rf /'
    run "${REPO_ROOT}/backup/sync.sh"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"non-negative integer"* ]]
}

@test "sync.sh: rejects zero RCLONE_TRANSFERS" {
    export GITPRESERVER_RCLONE_TRANSFERS=0
    run "${REPO_ROOT}/backup/sync.sh"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"positive integer"* ]]
}

@test "sync.sh: skips remote sync when GITPRESERVER_RCLONE_REMOTE is empty" {
    export GITPRESERVER_RETENTION_DAYS=0
    run "${REPO_ROOT}/backup/sync.sh"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"skipping remote sync"* ]]
    [[ "${output}" == *"Retention pruning disabled"* ]]
}

@test "sync.sh: encrypt without crypt_remote is an error" {
    export GITPRESERVER_RCLONE_REMOTE=b2-remote
    export GITPRESERVER_ENCRYPT=true
    export GITPRESERVER_RETENTION_DAYS=0
    run "${REPO_ROOT}/backup/sync.sh"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"GITPRESERVER_CRYPT_REMOTE is not set"* ]]
}

@test "sync.sh: dry-run passes --dry-run to rclone" {
    shim_dir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${shim_dir}"
    cat > "${shim_dir}/rclone" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${BATS_TEST_TMPDIR}/rclone-args"
SHIM
    chmod +x "${shim_dir}/rclone"
    export PATH="${shim_dir}:${PATH}"

    export GITPRESERVER_RCLONE_REMOTE=b2-remote
    export GITPRESERVER_DRY_RUN=true
    export GITPRESERVER_RETENTION_DAYS=0
    run "${REPO_ROOT}/backup/sync.sh"
    [ "${status}" -eq 0 ]
    grep -q -- '--dry-run' "${BATS_TEST_TMPDIR}/rclone-args"
}

@test "sync.sh: routes sync through crypt remote when ENCRYPT=true" {
    shim_dir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${shim_dir}"
    cat > "${shim_dir}/rclone" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${BATS_TEST_TMPDIR}/rclone-args"
SHIM
    chmod +x "${shim_dir}/rclone"
    export PATH="${shim_dir}:${PATH}"

    export GITPRESERVER_RCLONE_REMOTE=b2
    export GITPRESERVER_ENCRYPT=true
    export GITPRESERVER_CRYPT_REMOTE=mycrypt
    export GITPRESERVER_DRY_RUN=true
    export GITPRESERVER_RETENTION_DAYS=0

    run "${REPO_ROOT}/backup/sync.sh"
    [ "${status}" -eq 0 ]
    # rclone must be called with the crypt remote as the destination
    grep -q "^mycrypt:" "${BATS_TEST_TMPDIR}/rclone-args"
    # and must NOT use the plain b2 remote directly
    ! grep -q "^b2:" "${BATS_TEST_TMPDIR}/rclone-args"
}

@test "sync.sh: retention pruning leaves recent snapshots intact" {
    # Build a fake backup tree with one recent and one ancient date dir.
    mkdir -p "${GITPRESERVER_BACKUP_DIR}/2020-01-01/repos"
    mkdir -p "${GITPRESERVER_BACKUP_DIR}/2099-12-31/repos"
    # Backdate the ancient one well past the retention window.
    touch -t 200001010000 "${GITPRESERVER_BACKUP_DIR}/2020-01-01"

    export GITPRESERVER_RETENTION_DAYS=7
    run "${REPO_ROOT}/backup/sync.sh"
    [ "${status}" -eq 0 ]
    [ ! -d "${GITPRESERVER_BACKUP_DIR}/2020-01-01" ]
    [ -d "${GITPRESERVER_BACKUP_DIR}/2099-12-31" ]
}
