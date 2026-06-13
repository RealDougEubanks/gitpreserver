#!/usr/bin/env bats

load test_helper

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Build a minimal shim directory with stubs for supercronic and python3.
# Caller may override individual stubs after calling this.
setup_daemon_shims() {
    local shim_dir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${shim_dir}"
    # supercronic default stub: capture the crontab file then exit
    cat > "${shim_dir}/supercronic" <<SHIM
#!/usr/bin/env bash
cp "\$1" "${BATS_TEST_TMPDIR}/captured.cron"
exit 0
SHIM
    # python3 stub: no-op (web server is not under test here)
    printf '#!/usr/bin/env bash\n' > "${shim_dir}/python3"
    chmod +x "${shim_dir}/supercronic" "${shim_dir}/python3"
    printf '%s' "${shim_dir}"
}

# ---------------------------------------------------------------------------
# Status file initialisation
# ---------------------------------------------------------------------------

@test "daemon-start.sh: writes idle status file when none exists" {
    shim_dir="$(setup_daemon_shims)"
    export PATH="${shim_dir}:${PATH}"
    export GITPRESERVER_STATUS_FILE="${BATS_TEST_TMPDIR}/status.json"
    unset GITPRESERVER_SCHEDULE

    run "${REPO_ROOT}/docker/daemon-start.sh"
    [ "${status}" -eq 0 ]
    [ -f "${GITPRESERVER_STATUS_FILE}" ]
    [ "$(jq -r '.status' "${GITPRESERVER_STATUS_FILE}")" = "idle" ]
}

@test "daemon-start.sh: does not overwrite an existing status file" {
    shim_dir="$(setup_daemon_shims)"
    export PATH="${shim_dir}:${PATH}"
    export GITPRESERVER_STATUS_FILE="${BATS_TEST_TMPDIR}/status.json"
    printf '{"status":"success","last_run":"2026-05-22T02:00:00Z","message":"ok"}\n' \
        > "${GITPRESERVER_STATUS_FILE}"

    run "${REPO_ROOT}/docker/daemon-start.sh"
    [ "${status}" -eq 0 ]
    [ "$(jq -r '.status' "${GITPRESERVER_STATUS_FILE}")" = "success" ]
}

# ---------------------------------------------------------------------------
# Crontab generation
# ---------------------------------------------------------------------------

@test "daemon-start.sh: builds crontab containing the schedule and run-stages.sh" {
    shim_dir="$(setup_daemon_shims)"
    export PATH="${shim_dir}:${PATH}"
    export GITPRESERVER_STATUS_FILE="${BATS_TEST_TMPDIR}/status.json"
    export GITPRESERVER_SCHEDULE="0 4 * * 1"

    run "${REPO_ROOT}/docker/daemon-start.sh"
    [ "${status}" -eq 0 ]
    [ -f "${BATS_TEST_TMPDIR}/captured.cron" ]
    grep -q "0 4 \* \* 1" "${BATS_TEST_TMPDIR}/captured.cron"
    grep -q "run-stages.sh" "${BATS_TEST_TMPDIR}/captured.cron"
}

@test "daemon-start.sh: defaults to '0 2 * * 0' when GITPRESERVER_SCHEDULE is unset" {
    shim_dir="$(setup_daemon_shims)"
    export PATH="${shim_dir}:${PATH}"
    export GITPRESERVER_STATUS_FILE="${BATS_TEST_TMPDIR}/status.json"
    unset GITPRESERVER_SCHEDULE

    run "${REPO_ROOT}/docker/daemon-start.sh"
    [ "${status}" -eq 0 ]
    grep -q "0 2 \* \* 0" "${BATS_TEST_TMPDIR}/captured.cron"
}

# ---------------------------------------------------------------------------
# Schedule validation (command-injection hardening)
# ---------------------------------------------------------------------------

@test "daemon-start.sh: accepts a valid 5-field cron expression with operators" {
    shim_dir="$(setup_daemon_shims)"
    export PATH="${shim_dir}:${PATH}"
    export GITPRESERVER_STATUS_FILE="${BATS_TEST_TMPDIR}/status.json"
    export GITPRESERVER_SCHEDULE="*/15 0-6 1,15 * 1-5"

    run "${REPO_ROOT}/docker/daemon-start.sh"
    [ "${status}" -eq 0 ]
    grep -q "run-stages.sh" "${BATS_TEST_TMPDIR}/captured.cron"
}

@test "daemon-start.sh: accepts the @daily shortcut" {
    shim_dir="$(setup_daemon_shims)"
    export PATH="${shim_dir}:${PATH}"
    export GITPRESERVER_STATUS_FILE="${BATS_TEST_TMPDIR}/status.json"
    export GITPRESERVER_SCHEDULE="@daily"

    run "${REPO_ROOT}/docker/daemon-start.sh"
    [ "${status}" -eq 0 ]
    grep -q "@daily flock" "${BATS_TEST_TMPDIR}/captured.cron"
}

@test "daemon-start.sh: rejects a schedule containing shell metacharacters" {
    shim_dir="$(setup_daemon_shims)"
    export PATH="${shim_dir}:${PATH}"
    export GITPRESERVER_STATUS_FILE="${BATS_TEST_TMPDIR}/status.json"
    export GITPRESERVER_SCHEDULE='* * * * * x; rm -rf /'

    run "${REPO_ROOT}/docker/daemon-start.sh"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"not a valid cron expression"* ]]
    [ ! -f "${BATS_TEST_TMPDIR}/captured.cron" ]
}

@test "daemon-start.sh: rejects a schedule with too many fields" {
    shim_dir="$(setup_daemon_shims)"
    export PATH="${shim_dir}:${PATH}"
    export GITPRESERVER_STATUS_FILE="${BATS_TEST_TMPDIR}/status.json"
    export GITPRESERVER_SCHEDULE="0 2 * * 0 extra"

    run "${REPO_ROOT}/docker/daemon-start.sh"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"not a valid cron expression"* ]]
    [ ! -f "${BATS_TEST_TMPDIR}/captured.cron" ]
}
