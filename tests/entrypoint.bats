#!/usr/bin/env bats

load test_helper

# ---------------------------------------------------------------------------
# entrypoint.sh requires root for groupmod/usermod/chown. We stub those out
# so the MODE logic (which runs as the last step) is reachable without root.
#
# Stubs:
#   id     — always returns 1000 (matches default PUID/PGID so usermod/
#             groupmod branches are skipped entirely)
#   chown  — no-op (chown -R ... || true means failures are tolerated anyway)
#   gosu   — records its arguments to a file, then execs the remaining args
# ---------------------------------------------------------------------------

setup_entrypoint_shims() {
    local shim_dir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${shim_dir}"

    printf '#!/usr/bin/env bash\necho 1000\n' > "${shim_dir}/id"
    printf '#!/usr/bin/env bash\nexit 0\n'    > "${shim_dir}/chown"

    # gosu shim: first arg is user:group — skip it, record the rest, exec it
    cat > "${shim_dir}/gosu" <<SHIM
#!/usr/bin/env bash
shift
printf '%s\n' "\$@" > "${BATS_TEST_TMPDIR}/gosu-args"
exec "\$@"
SHIM

    chmod +x "${shim_dir}/id" "${shim_dir}/chown" "${shim_dir}/gosu"
    printf '%s' "${shim_dir}"
}

# ---------------------------------------------------------------------------
# MODE validation
# ---------------------------------------------------------------------------

@test "entrypoint.sh: rejects invalid GITPRESERVER_MODE with error message" {
    shim_dir="$(setup_entrypoint_shims)"
    export PATH="${shim_dir}:${PATH}"
    export GITPRESERVER_MODE=turbolaunch

    run "${REPO_ROOT}/docker/entrypoint.sh" run-stages.sh
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"GITPRESERVER_MODE"* ]]
    [[ "${output}" == *"turbolaunch"* ]]
}

@test "entrypoint.sh: daemon mode passes daemon-start.sh to gosu" {
    shim_dir="$(setup_entrypoint_shims)"
    # Stub daemon-start.sh so gosu can exec it without the real deps
    printf '#!/usr/bin/env bash\nexit 0\n' > "${shim_dir}/daemon-start.sh"
    chmod +x "${shim_dir}/daemon-start.sh"
    export PATH="${shim_dir}:${PATH}"
    export GITPRESERVER_MODE=daemon

    run "${REPO_ROOT}/docker/entrypoint.sh" run-stages.sh
    [ "${status}" -eq 0 ]
    grep -q "daemon-start.sh" "${BATS_TEST_TMPDIR}/gosu-args"
}

@test "entrypoint.sh: oneshot mode passes original command to gosu" {
    shim_dir="$(setup_entrypoint_shims)"
    printf '#!/usr/bin/env bash\nexit 0\n' > "${shim_dir}/run-stages.sh"
    chmod +x "${shim_dir}/run-stages.sh"
    export PATH="${shim_dir}:${PATH}"
    export GITPRESERVER_MODE=oneshot

    run "${REPO_ROOT}/docker/entrypoint.sh" run-stages.sh
    [ "${status}" -eq 0 ]
    grep -q "run-stages.sh" "${BATS_TEST_TMPDIR}/gosu-args"
}
