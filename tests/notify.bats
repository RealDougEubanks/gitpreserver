#!/usr/bin/env bats

load test_helper

setup_curl_shim() {
    local shim_dir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${shim_dir}"
    cat > "${shim_dir}/curl" <<'SHIM'
#!/usr/bin/env bash
# Record args and body to files for inspection
printf '%s\n' "$@" >> "${BATS_TEST_TMPDIR}/curl-args"
# Capture -d payload
for i in "$@"; do
    if [[ "${prev}" == "-d" ]]; then
        printf '%s' "${i}" > "${BATS_TEST_TMPDIR}/curl-payload"
    fi
    prev="${i}"
done
exit 0
SHIM
    chmod +x "${shim_dir}/curl"
    printf '%s' "${shim_dir}"
}

@test "notify.sh: exits 0 silently when WEBHOOK_URL is unset" {
    unset GITPRESERVER_WEBHOOK_URL
    run "${REPO_ROOT}/backup/notify.sh" "success" "All stages complete."
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
}

@test "notify.sh: exits 0 silently when WEBHOOK_URL is empty" {
    export GITPRESERVER_WEBHOOK_URL=""
    run "${REPO_ROOT}/backup/notify.sh" "success" "All stages complete."
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
}

@test "notify.sh: sends POST to generic URL on success" {
    shim_dir="$(setup_curl_shim)"
    export PATH="${shim_dir}:${PATH}"
    export GITPRESERVER_WEBHOOK_URL="https://example.com/hook"
    export GITPRESERVER_USERNAME=alice
    export GITPRESERVER_HOST_TYPE=github

    run "${REPO_ROOT}/backup/notify.sh" "success" "All stages complete."
    [ "${status}" -eq 0 ]
    grep -q "https://example.com/hook" "${BATS_TEST_TMPDIR}/curl-args"
    grep -q '"status"' "${BATS_TEST_TMPDIR}/curl-payload"
    grep -q '"success"' "${BATS_TEST_TMPDIR}/curl-payload"
}

@test "notify.sh: sends POST to Slack URL with text field" {
    shim_dir="$(setup_curl_shim)"
    export PATH="${shim_dir}:${PATH}"
    export GITPRESERVER_WEBHOOK_URL="https://hooks.slack.com/services/T123/B456/token"
    export GITPRESERVER_USERNAME=alice
    export GITPRESERVER_HOST_TYPE=github

    run "${REPO_ROOT}/backup/notify.sh" "success" "All stages complete."
    [ "${status}" -eq 0 ]
    grep -q '"text"' "${BATS_TEST_TMPDIR}/curl-payload"
}

@test "notify.sh: sends POST to Discord URL with embeds field" {
    shim_dir="$(setup_curl_shim)"
    export PATH="${shim_dir}:${PATH}"
    export GITPRESERVER_WEBHOOK_URL="https://discord.com/api/webhooks/123/token"
    export GITPRESERVER_USERNAME=alice
    export GITPRESERVER_HOST_TYPE=github

    run "${REPO_ROOT}/backup/notify.sh" "failed" "Pipeline aborted during: mirror"
    [ "${status}" -eq 0 ]
    grep -q '"embeds"' "${BATS_TEST_TMPDIR}/curl-payload"
}

@test "notify.sh: WEBHOOK_ON=failure suppresses success notifications" {
    shim_dir="$(setup_curl_shim)"
    export PATH="${shim_dir}:${PATH}"
    export GITPRESERVER_WEBHOOK_URL="https://example.com/hook"
    export GITPRESERVER_WEBHOOK_ON=failure

    run "${REPO_ROOT}/backup/notify.sh" "success" "All stages complete."
    [ "${status}" -eq 0 ]
    [ ! -f "${BATS_TEST_TMPDIR}/curl-args" ]
}

@test "notify.sh: WEBHOOK_ON=failure fires on failure" {
    shim_dir="$(setup_curl_shim)"
    export PATH="${shim_dir}:${PATH}"
    export GITPRESERVER_WEBHOOK_URL="https://example.com/hook"
    export GITPRESERVER_WEBHOOK_ON=failure
    export GITPRESERVER_USERNAME=alice
    export GITPRESERVER_HOST_TYPE=github

    run "${REPO_ROOT}/backup/notify.sh" "failed" "Pipeline aborted during: mirror"
    [ "${status}" -eq 0 ]
    [ -f "${BATS_TEST_TMPDIR}/curl-args" ]
}

@test "notify.sh: WEBHOOK_ON=success suppresses failure notifications" {
    shim_dir="$(setup_curl_shim)"
    export PATH="${shim_dir}:${PATH}"
    export GITPRESERVER_WEBHOOK_URL="https://example.com/hook"
    export GITPRESERVER_WEBHOOK_ON=success

    run "${REPO_ROOT}/backup/notify.sh" "failed" "Pipeline aborted during: sync"
    [ "${status}" -eq 0 ]
    [ ! -f "${BATS_TEST_TMPDIR}/curl-args" ]
}

@test "notify.sh: curl failure logs a warning but does not fail the pipeline" {
    shim_dir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${shim_dir}"
    # curl that always fails (simulating an HTTP 5xx under -f).
    cat > "${shim_dir}/curl" <<'SHIM'
#!/usr/bin/env bash
printf '500'
exit 22
SHIM
    chmod +x "${shim_dir}/curl"
    export PATH="${shim_dir}:${PATH}"

    export GITPRESERVER_WEBHOOK_URL="https://example.com/hook"
    export GITPRESERVER_USERNAME=alice
    export GITPRESERVER_HOST_TYPE=github

    run "${REPO_ROOT}/backup/notify.sh" "success" "All stages complete."
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"WARNING: webhook delivery failed"* ]]
}

@test "notify.sh: passes --max-time to curl" {
    shim_dir="$(setup_curl_shim)"
    export PATH="${shim_dir}:${PATH}"
    export GITPRESERVER_WEBHOOK_URL="https://example.com/hook"
    export GITPRESERVER_USERNAME=alice
    export GITPRESERVER_HOST_TYPE=github

    run "${REPO_ROOT}/backup/notify.sh" "success" "All stages complete."
    [ "${status}" -eq 0 ]
    grep -q -- '--max-time' "${BATS_TEST_TMPDIR}/curl-args"
}

@test "notify.sh: rejects non-http(s) scheme and skips that URL" {
    shim_dir="$(setup_curl_shim)"
    export PATH="${shim_dir}:${PATH}"
    export GITPRESERVER_WEBHOOK_URL="file:///etc/passwd"
    export GITPRESERVER_USERNAME=alice
    export GITPRESERVER_HOST_TYPE=github

    run "${REPO_ROOT}/backup/notify.sh" "success" "All stages complete."
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"unsupported scheme"* ]]
    [ ! -f "${BATS_TEST_TMPDIR}/curl-args" ]
}

@test "notify.sh: rejects http:// unless insecure opt-in is set" {
    shim_dir="$(setup_curl_shim)"
    export PATH="${shim_dir}:${PATH}"
    export GITPRESERVER_WEBHOOK_URL="http://lan.example/hook"
    export GITPRESERVER_USERNAME=alice
    export GITPRESERVER_HOST_TYPE=github

    run "${REPO_ROOT}/backup/notify.sh" "success" "All stages complete."
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"refusing insecure http"* ]]
    [ ! -f "${BATS_TEST_TMPDIR}/curl-args" ]
}

@test "notify.sh: allows http:// when GITPRESERVER_WEBHOOK_ALLOW_INSECURE=true" {
    shim_dir="$(setup_curl_shim)"
    export PATH="${shim_dir}:${PATH}"
    export GITPRESERVER_WEBHOOK_URL="http://lan.example/hook"
    export GITPRESERVER_WEBHOOK_ALLOW_INSECURE=true
    export GITPRESERVER_USERNAME=alice
    export GITPRESERVER_HOST_TYPE=github

    run "${REPO_ROOT}/backup/notify.sh" "success" "All stages complete."
    [ "${status}" -eq 0 ]
    grep -q "http://lan.example/hook" "${BATS_TEST_TMPDIR}/curl-args"
}

@test "notify.sh: URL starting with dash is passed after -- not as an option" {
    shim_dir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${shim_dir}"
    # Record args; succeed only if a literal '--' precedes the URL token.
    cat > "${shim_dir}/curl" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "${BATS_TEST_TMPDIR}/curl-args"
printf '200'
exit 0
SHIM
    chmod +x "${shim_dir}/curl"
    export PATH="${shim_dir}:${PATH}"

    # A scheme is still required, so use a valid https URL whose path the test
    # asserts is preceded by '--'. We craft a URL that is valid but whose
    # presence after '--' we can verify.
    export GITPRESERVER_WEBHOOK_URL="https://example.com/hook"
    export GITPRESERVER_USERNAME=alice
    export GITPRESERVER_HOST_TYPE=github

    run "${REPO_ROOT}/backup/notify.sh" "success" "All stages complete."
    [ "${status}" -eq 0 ]
    # Confirm '--' appears immediately before the URL in the arg stream.
    grep -A1 -- '^--$' "${BATS_TEST_TMPDIR}/curl-args" | grep -q "https://example.com/hook"
}

@test "notify.sh: sends to multiple comma-separated URLs" {
    shim_dir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${shim_dir}"
    cat > "${shim_dir}/curl" <<'SHIM'
#!/usr/bin/env bash
for arg in "$@"; do
    [[ "${arg}" == https://* ]] && printf '%s\n' "${arg}" >> "${BATS_TEST_TMPDIR}/urls-called"
done
exit 0
SHIM
    chmod +x "${shim_dir}/curl"
    export PATH="${shim_dir}:${PATH}"

    export GITPRESERVER_WEBHOOK_URL="https://example.com/hook1,https://example.com/hook2"
    export GITPRESERVER_USERNAME=alice
    export GITPRESERVER_HOST_TYPE=github

    run "${REPO_ROOT}/backup/notify.sh" "success" "All stages complete."
    [ "${status}" -eq 0 ]
    grep -q "https://example.com/hook1" "${BATS_TEST_TMPDIR}/urls-called"
    grep -q "https://example.com/hook2" "${BATS_TEST_TMPDIR}/urls-called"
}
