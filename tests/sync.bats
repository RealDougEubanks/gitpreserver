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

@test "sync.sh: encrypt with mismatched crypt remote count is an error" {
    export GITPRESERVER_RCLONE_REMOTE=b2,s3
    export GITPRESERVER_ENCRYPT=true
    export GITPRESERVER_CRYPT_REMOTE=b2-crypt
    export GITPRESERVER_RETENTION_DAYS=0
    run "${REPO_ROOT}/backup/sync.sh"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"must match 1-to-1"* ]]
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
    grep -q "^mycrypt:" "${BATS_TEST_TMPDIR}/rclone-args"
    ! grep -q "^b2:" "${BATS_TEST_TMPDIR}/rclone-args"
}

@test "sync.sh: multiple remotes each receive a separate rclone call" {
    shim_dir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${shim_dir}"
    # Append each call's destination to a log file
    cat > "${shim_dir}/rclone" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "${BATS_TEST_TMPDIR}/rclone-calls"
SHIM
    chmod +x "${shim_dir}/rclone"
    export PATH="${shim_dir}:${PATH}"

    export GITPRESERVER_RCLONE_REMOTE=b2-remote,s3-remote
    export GITPRESERVER_DRY_RUN=true
    export GITPRESERVER_RETENTION_DAYS=0

    run "${REPO_ROOT}/backup/sync.sh"
    [ "${status}" -eq 0 ]
    grep -q "^b2-remote:" "${BATS_TEST_TMPDIR}/rclone-calls"
    grep -q "^s3-remote:" "${BATS_TEST_TMPDIR}/rclone-calls"
}

@test "sync.sh: multiple encrypted remotes each use their paired crypt remote" {
    shim_dir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${shim_dir}"
    cat > "${shim_dir}/rclone" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "${BATS_TEST_TMPDIR}/rclone-calls"
SHIM
    chmod +x "${shim_dir}/rclone"
    export PATH="${shim_dir}:${PATH}"

    export GITPRESERVER_RCLONE_REMOTE=b2,s3
    export GITPRESERVER_ENCRYPT=true
    export GITPRESERVER_CRYPT_REMOTE=b2-crypt,s3-crypt
    export GITPRESERVER_DRY_RUN=true
    export GITPRESERVER_RETENTION_DAYS=0

    run "${REPO_ROOT}/backup/sync.sh"
    [ "${status}" -eq 0 ]
    grep -q "^b2-crypt:" "${BATS_TEST_TMPDIR}/rclone-calls"
    grep -q "^s3-crypt:" "${BATS_TEST_TMPDIR}/rclone-calls"
    ! grep -q "^b2:" "${BATS_TEST_TMPDIR}/rclone-calls"
    ! grep -q "^s3:" "${BATS_TEST_TMPDIR}/rclone-calls"
}

@test "sync.sh: one failing remote does not stop the others, pruning still runs, exit non-zero" {
    shim_dir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${shim_dir}"
    # rclone shim: record the destination; fail only for the s3-fail remote.
    cat > "${shim_dir}/rclone" <<'SHIM'
#!/usr/bin/env bash
dest=""
for arg in "$@"; do
    [[ "${arg}" == *:* ]] && dest="${arg}"
done
printf '%s\n' "${dest}" >> "${BATS_TEST_TMPDIR}/rclone-calls"
if [[ "${dest}" == s3-fail:* ]]; then
    echo "simulated rclone failure" >&2
    exit 1
fi
exit 0
SHIM
    chmod +x "${shim_dir}/rclone"
    export PATH="${shim_dir}:${PATH}"

    # Middle remote (#2) fails; #1 and #3 must still be attempted.
    export GITPRESERVER_RCLONE_REMOTE="b2-ok,s3-fail,gdrive-ok"
    export GITPRESERVER_RETENTION_DAYS=0

    run "${REPO_ROOT}/backup/sync.sh"
    [ "${status}" -ne 0 ]
    grep -q "^b2-ok:" "${BATS_TEST_TMPDIR}/rclone-calls"
    grep -q "^s3-fail:" "${BATS_TEST_TMPDIR}/rclone-calls"
    grep -q "^gdrive-ok:" "${BATS_TEST_TMPDIR}/rclone-calls"
    [[ "${output}" == *"ERROR: rclone sync to s3-fail:"* ]]
    [[ "${output}" == *"remote(s) failed to sync: s3-fail"* ]]
    # Retention pruning block ran despite the failure.
    [[ "${output}" == *"Retention pruning disabled"* ]]
}

@test "sync.sh: failing remote with active pruning still prunes old snapshots" {
    shim_dir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${shim_dir}"
    cat > "${shim_dir}/rclone" <<'SHIM'
#!/usr/bin/env bash
echo "simulated rclone failure" >&2
exit 1
SHIM
    chmod +x "${shim_dir}/rclone"
    export PATH="${shim_dir}:${PATH}"

    mkdir -p "${GITPRESERVER_BACKUP_DIR}/2020-01-01/repos"
    touch -t 200001010000 "${GITPRESERVER_BACKUP_DIR}/2020-01-01"

    export GITPRESERVER_RCLONE_REMOTE="b2-fail"
    export GITPRESERVER_RETENTION_DAYS=7

    run "${REPO_ROOT}/backup/sync.sh"
    [ "${status}" -ne 0 ]
    # Pruning ran even though the remote failed.
    [ ! -d "${GITPRESERVER_BACKUP_DIR}/2020-01-01" ]
}

@test "sync.sh: retention pruning leaves recent snapshots intact" {
    mkdir -p "${GITPRESERVER_BACKUP_DIR}/2020-01-01/repos"
    mkdir -p "${GITPRESERVER_BACKUP_DIR}/2099-12-31/repos"
    touch -t 200001010000 "${GITPRESERVER_BACKUP_DIR}/2020-01-01"

    export GITPRESERVER_RETENTION_DAYS=7
    run "${REPO_ROOT}/backup/sync.sh"
    [ "${status}" -eq 0 ]
    [ ! -d "${GITPRESERVER_BACKUP_DIR}/2020-01-01" ]
    [ -d "${GITPRESERVER_BACKUP_DIR}/2099-12-31" ]
}
