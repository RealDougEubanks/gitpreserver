#!/usr/bin/env bash
#
# GitPreserver local integration harness.
#
# Drives the REAL backup scripts (no mocks) against rclone's local filesystem
# backend and a throwaway local HTTP server, so you can confirm the actual
# behavior and outputs before merging:
#
#   * sync.sh    — single/multiple local destinations, partial failure,
#                  dry-run, encryption (rclone crypt), retention pruning,
#                  input validation.
#   * notify.sh  — real webhook delivery to a local listener, payload shaping
#                  per service, scheme rejection, WEBHOOK_ON filtering, fan-out.
#   * run-stages.sh / mirror.sh / metadata.sh — exercised end-to-end ONLY when a
#                  .env with real credentials is present (see CREDENTIALED below);
#                  skipped cleanly otherwise.
#
# Requirements: rclone, jq, python3, git, bash 4+. Everything runs against
# temporary directories under $TMPDIR and is removed on exit.
#
# Usage:
#   tests/local-sync-test.sh            # run the local (no-creds) suite
#   GITPRESERVER_TEST_ENV=path/to/.env tests/local-sync-test.sh
#
# CREDENTIALED: if a .env with GITPRESERVER_TOKEN + GITPRESERVER_USERNAME exists
# at the repo root (or $GITPRESERVER_TEST_ENV) AND ghorg + gh are installed, the
# full mirror→metadata→sync pipeline runs against the real git host into a local
# destination. The token/username are read by name (the .env is NOT sourced).
# When anything is missing, those cases are reported as SKIPPED, not failed.
#
# Exit code: 0 if every executed assertion passed, 1 otherwise — suitable as a
# pre-merge gate.

# NOTE: deliberately no `set -e` at the top level — several cases assert on
# non-zero exits from the scripts under test, and an aborting harness would
# mask the very behavior we want to observe.
set -uo pipefail

# ---------------------------------------------------------------------------
# Locations
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BACKUP_DIR_SCRIPTS="${REPO_ROOT}/backup"
SYNC_SH="${BACKUP_DIR_SCRIPTS}/sync.sh"
NOTIFY_SH="${BACKUP_DIR_SCRIPTS}/notify.sh"
RUN_STAGES_SH="${BACKUP_DIR_SCRIPTS}/run-stages.sh"

# ---------------------------------------------------------------------------
# Pretty output
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
    C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_YELLOW=$'\033[33m'
    C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'; C_RESET=$'\033[0m'
else
    C_GREEN=""; C_RED=""; C_YELLOW=""; C_BOLD=""; C_DIM=""; C_RESET=""
fi

PASS=0; FAIL=0; SKIP=0
declare -a FAILED_NAMES=()

section() { printf '\n%s== %s ==%s\n' "${C_BOLD}" "$1" "${C_RESET}"; }

pass() { PASS=$((PASS + 1)); printf '  %sPASS%s %s\n' "${C_GREEN}" "${C_RESET}" "$1"; }
skip() { SKIP=$((SKIP + 1)); printf '  %sSKIP%s %s\n' "${C_YELLOW}" "${C_RESET}" "$1"; }
fail() {
    FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1")
    printf '  %sFAIL%s %s\n' "${C_RED}" "${C_RESET}" "$1"
    [[ -n "${2:-}" ]] && printf '       %s%s%s\n' "${C_DIM}" "$2" "${C_RESET}"
}

# assert_eq <actual> <expected> <description>
assert_eq() {
    if [[ "$1" == "$2" ]]; then pass "$3"; else fail "$3" "expected '$2', got '$1'"; fi
}
# assert_contains <haystack> <needle> <description>
assert_contains() {
    if printf '%s' "$1" | grep -qF -- "$2"; then pass "$3"
    else fail "$3" "output did not contain: $2"; fi
}
# assert_not_contains <haystack> <needle> <description>
assert_not_contains() {
    if printf '%s' "$1" | grep -qF -- "$2"; then fail "$3" "output unexpectedly contained: $2"
    else pass "$3"; fi
}
# assert_file_exists <path> <description>
assert_file_exists() {
    if [[ -e "$1" ]]; then pass "$2"; else fail "$2" "missing: $1"; fi
}
# assert_file_absent <path> <description>
assert_file_absent() {
    if [[ ! -e "$1" ]]; then pass "$2"; else fail "$2" "should not exist: $1"; fi
}

# ---------------------------------------------------------------------------
# Prerequisites
# ---------------------------------------------------------------------------
section "Prerequisites"
missing=0
for tool in rclone jq python3 git bash; do
    if command -v "$tool" >/dev/null 2>&1; then
        pass "$tool available ($("$tool" --version 2>/dev/null | head -1 | cut -c1-40))"
    else
        fail "$tool available" "install $tool — the local suite cannot run without it"
        missing=1
    fi
done
for f in "${SYNC_SH}" "${NOTIFY_SH}" "${RUN_STAGES_SH}"; do
    [[ -f "$f" ]] || { fail "script present: $f" "not found"; missing=1; }
done
if (( missing )); then
    printf '\n%sAborting: prerequisites missing.%s\n' "${C_RED}" "${C_RESET}"
    exit 1
fi

# ---------------------------------------------------------------------------
# Workspace
# ---------------------------------------------------------------------------
WS="$(mktemp -d "${TMPDIR:-/tmp}/gitpreserver-itest.XXXXXX")"
WEBHOOK_PID=""
cleanup() {
    [[ -n "${WEBHOOK_PID}" ]] && kill "${WEBHOOK_PID}" 2>/dev/null
    rm -rf "${WS}"
}
trap cleanup EXIT INT TERM

# rclone config with alias remotes pointing at local dirs + a crypt remote.
# Using `alias` (rather than bare `local`) lets each destination map to its own
# directory while sync.sh appends the shared GITPRESERVER_RCLONE_PATH.
RCLONE_CONF="${WS}/rclone.conf"
DEST1="${WS}/dest1"; DEST2="${WS}/dest2"; DESTC="${WS}/destc"
mkdir -p "${DEST1}" "${DEST2}" "${DESTC}"
CRYPT_PASS_OBSCURED="$(rclone obscure 'gitpreserver-local-test-pass')"
cat > "${RCLONE_CONF}" <<EOF
[d1]
type = alias
remote = ${DEST1}

[d2]
type = alias
remote = ${DEST2}

[cbase]
type = alias
remote = ${DESTC}

[cryptd1]
type = crypt
remote = cbase:enc
password = ${CRYPT_PASS_OBSCURED}
filename_encryption = standard
directory_name_encryption = true
EOF
export RCLONE_CONFIG="${RCLONE_CONF}"

# Build a backup snapshot dir with recognizable content to sync.
make_snapshot() {
    local root="$1" date="${2:-2026-06-12}"
    local repo="${root}/${date}/repos/example.git"
    mkdir -p "${repo}"
    printf 'hello gitpreserver %s\n' "${date}" > "${repo}/HEAD"
    printf '[]\n' > "${root}/${date}/repos/example.issues.json"
}

RC_FILE="${WS}/.last_rc"
last_rc() { cat "${RC_FILE}" 2>/dev/null; }
# run_script <path> <VAR=val...> — runs the script under command substitution.
# Writes the exit code to RC_FILE (a real file, so it survives the command-
# substitution subshell, where a plain LAST_RC=$? assignment would be lost).
# Usage: out=$(run_script "$SCRIPT" VAR=val); then check "$(last_rc)".
run_script() {
    local script="$1"; shift
    env "$@" bash "${script}" 2>&1
    echo "$?" > "${RC_FILE}"
}

# ===========================================================================
section "sync.sh — local destinations (real rclone)"
# ===========================================================================

# --- single destination -----------------------------------------------------
B="${WS}/b_single"; make_snapshot "${B}"
out=$(run_script "${SYNC_SH}" \
    GITPRESERVER_BACKUP_DIR="${B}" \
    GITPRESERVER_RCLONE_REMOTE="d1" \
    GITPRESERVER_RETENTION_DAYS="0")
assert_eq "$(last_rc)" "0" "single dest: exit 0"
assert_contains "${out}" "Sync to d1:gitpreserver-backups complete." "single dest: logs completion"
assert_file_exists "${DEST1}/gitpreserver-backups/2026-06-12/repos/example.git/HEAD" "single dest: file landed on remote"
rm -rf "${DEST1:?}/"* 2>/dev/null

# --- multiple destinations ---------------------------------------------------
B="${WS}/b_multi"; make_snapshot "${B}"
out=$(run_script "${SYNC_SH}" \
    GITPRESERVER_BACKUP_DIR="${B}" \
    GITPRESERVER_RCLONE_REMOTE="d1,d2" \
    GITPRESERVER_RETENTION_DAYS="0")
assert_eq "$(last_rc)" "0" "multi dest: exit 0"
assert_file_exists "${DEST1}/gitpreserver-backups/2026-06-12/repos/example.git/HEAD" "multi dest: d1 received files"
assert_file_exists "${DEST2}/gitpreserver-backups/2026-06-12/repos/example.git/HEAD" "multi dest: d2 received files"
rm -rf "${DEST1:?}/"* "${DEST2:?}/"* 2>/dev/null

# --- one failing remote does not stop the others ----------------------------
B="${WS}/b_partial"; make_snapshot "${B}"
out=$(run_script "${SYNC_SH}" \
    GITPRESERVER_BACKUP_DIR="${B}" \
    GITPRESERVER_RCLONE_REMOTE="d1,nope,d2" \
    GITPRESERVER_RETENTION_DAYS="0" \
    GITPRESERVER_LOG_LEVEL="error")
assert_eq "$(last_rc)" "1" "partial failure: exit non-zero"
assert_file_exists "${DEST1}/gitpreserver-backups/2026-06-12/repos/example.git/HEAD" "partial failure: good remote d1 still synced"
assert_file_exists "${DEST2}/gitpreserver-backups/2026-06-12/repos/example.git/HEAD" "partial failure: good remote d2 still synced"
assert_contains "${out}" "remote(s) failed to sync" "partial failure: reports failed remotes"
assert_file_exists "${B}/.gitpreserver-failed-remotes" "partial failure: failed-remotes file written"
failed_content="$(cat "${B}/.gitpreserver-failed-remotes" 2>/dev/null)"
assert_contains "${failed_content}" "nope" "partial failure: failed-remotes names the bad remote"
rm -rf "${DEST1:?}/"* "${DEST2:?}/"* 2>/dev/null

# --- dry run writes nothing --------------------------------------------------
B="${WS}/b_dry"; make_snapshot "${B}"
out=$(run_script "${SYNC_SH}" \
    GITPRESERVER_BACKUP_DIR="${B}" \
    GITPRESERVER_RCLONE_REMOTE="d1" \
    GITPRESERVER_RETENTION_DAYS="0" \
    GITPRESERVER_DRY_RUN="true")
assert_eq "$(last_rc)" "0" "dry run: exit 0"
assert_contains "${out}" "DRY RUN" "dry run: logs DRY RUN"
assert_file_absent "${DEST1}/gitpreserver-backups/2026-06-12/repos/example.git/HEAD" "dry run: nothing written to remote"
rm -rf "${DEST1:?}/"* 2>/dev/null

# ===========================================================================
section "sync.sh — encryption (rclone crypt)"
# ===========================================================================

B="${WS}/b_crypt"; make_snapshot "${B}"
out=$(run_script "${SYNC_SH}" \
    GITPRESERVER_BACKUP_DIR="${B}" \
    GITPRESERVER_RCLONE_REMOTE="d1" \
    GITPRESERVER_CRYPT_REMOTE="cryptd1" \
    GITPRESERVER_ENCRYPT="true" \
    GITPRESERVER_RETENTION_DAYS="0")
assert_eq "$(last_rc)" "0" "crypt: exit 0"
# On-disk content must be encrypted: the plaintext filename HEAD must not appear.
on_disk="$(find "${DESTC}" -type f 2>/dev/null)"
assert_not_contains "${on_disk}" "example.git/HEAD" "crypt: plaintext path not present on disk"
assert_file_exists "${DESTC}/enc" "crypt: encrypted blobs written under enc/"
# But reading back THROUGH the crypt remote yields the original content.
decrypted="$(rclone cat "cryptd1:gitpreserver-backups/2026-06-12/repos/example.git/HEAD" 2>/dev/null)"
assert_contains "${decrypted}" "hello gitpreserver 2026-06-12" "crypt: decrypts back to original content"
rm -rf "${DESTC:?}/"* 2>/dev/null

# --- crypt count mismatch is rejected ---------------------------------------
B="${WS}/b_crypt_mismatch"; make_snapshot "${B}"
out=$(run_script "${SYNC_SH}" \
    GITPRESERVER_BACKUP_DIR="${B}" \
    GITPRESERVER_RCLONE_REMOTE="d1,d2" \
    GITPRESERVER_CRYPT_REMOTE="cryptd1" \
    GITPRESERVER_ENCRYPT="true" \
    GITPRESERVER_RETENTION_DAYS="0")
assert_eq "$(last_rc)" "1" "crypt mismatch: exit 1"
assert_contains "${out}" "must match 1-to-1" "crypt mismatch: explains the mismatch"

# ===========================================================================
section "sync.sh — retention pruning"
# ===========================================================================

B="${WS}/b_prune"
make_snapshot "${B}" "2020-01-01"   # old
make_snapshot "${B}" "2026-06-12"   # recent
touch -t 202001010000 "${B}/2020-01-01"   # force old mtime (BSD/GNU compatible)
out=$(run_script "${SYNC_SH}" \
    GITPRESERVER_BACKUP_DIR="${B}" \
    GITPRESERVER_RCLONE_REMOTE="" \
    GITPRESERVER_RETENTION_DAYS="30")
assert_eq "$(last_rc)" "0" "prune: exit 0 (local only)"
assert_contains "${out}" "skipping remote sync" "prune: no remote -> skips sync"
assert_file_absent "${B}/2020-01-01" "prune: old snapshot removed"
assert_file_exists "${B}/2026-06-12" "prune: recent snapshot kept"

# --- pruning disabled --------------------------------------------------------
B="${WS}/b_noprune"
make_snapshot "${B}" "2020-01-01"
touch -t 202001010000 "${B}/2020-01-01"
out=$(run_script "${SYNC_SH}" \
    GITPRESERVER_BACKUP_DIR="${B}" \
    GITPRESERVER_RCLONE_REMOTE="" \
    GITPRESERVER_RETENTION_DAYS="0")
assert_eq "$(last_rc)" "0" "prune disabled: exit 0"
assert_contains "${out}" "Retention pruning disabled" "prune disabled: logs disabled"
assert_file_exists "${B}/2020-01-01" "prune disabled: old snapshot retained"

# ===========================================================================
section "sync.sh — input validation"
# ===========================================================================

out=$(run_script "${SYNC_SH}" \
    GITPRESERVER_BACKUP_DIR="${WS}" \
    GITPRESERVER_RETENTION_DAYS="thirty")
assert_eq "$(last_rc)" "1" "validation: non-numeric RETENTION_DAYS rejected"
assert_contains "${out}" "RETENTION_DAYS" "validation: error names the bad var"

out=$(run_script "${SYNC_SH}" \
    GITPRESERVER_BACKUP_DIR="${WS}" \
    GITPRESERVER_RCLONE_REMOTE="d1" \
    GITPRESERVER_RCLONE_TRANSFERS="0")
assert_eq "$(last_rc)" "1" "validation: RCLONE_TRANSFERS=0 rejected"
assert_contains "${out}" "RCLONE_TRANSFERS" "validation: error names the bad var"

# ===========================================================================
section "notify.sh — real webhook delivery to a local listener"
# ===========================================================================

REQ_LOG="${WS}/webhook_requests.log"
PORT_FILE="${WS}/webhook_port"
: > "${REQ_LOG}"
cat > "${WS}/webhook_server.py" <<'PY'
import sys, http.server, socketserver
req_log, port_file = sys.argv[1], sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get('Content-Length', 0) or 0)
        body = self.rfile.read(n).decode('utf-8', 'replace')
        with open(req_log, 'a') as f:
            f.write(body + "\n")
        self.send_response(200); self.end_headers(); self.wfile.write(b'ok')
    def log_message(self, *a):  # silence
        pass
srv = socketserver.TCPServer(('127.0.0.1', 0), H)
with open(port_file, 'w') as f:
    f.write(str(srv.server_address[1]))
srv.serve_forever()
PY
python3 "${WS}/webhook_server.py" "${REQ_LOG}" "${PORT_FILE}" &
WEBHOOK_PID=$!
# Wait for the server to report its port.
for _ in $(seq 1 50); do [[ -s "${PORT_FILE}" ]] && break; sleep 0.1; done
PORT="$(cat "${PORT_FILE}" 2>/dev/null)"
if [[ -z "${PORT}" ]]; then
    fail "notify: local webhook server started" "server did not report a port"
else
    pass "notify: local webhook server started on 127.0.0.1:${PORT}"
fi

req_count() { wc -l < "${REQ_LOG}" | tr -d ' '; }
last_body() { tail -1 "${REQ_LOG}"; }

# --- generic JSON payload delivered -----------------------------------------
# notify.sh takes positional args (status, message), so call it directly rather
# than through the env-only run_script helper.
: > "${REQ_LOG}"
out="$(env GITPRESERVER_WEBHOOK_URL="http://127.0.0.1:${PORT}/" \
    GITPRESERVER_WEBHOOK_ALLOW_INSECURE="true" \
    GITPRESERVER_USERNAME="octocat" \
    GITPRESERVER_HOST_TYPE="github" \
    bash "${NOTIFY_SH}" "success" "local sync test" 2>&1)"
rc=$?
assert_eq "${rc}" "0" "notify generic: exit 0"
assert_eq "$(req_count)" "1" "notify generic: server received exactly one POST"
body="$(last_body)"
assert_contains "${body}" '"status":"success"' "notify generic: payload has status"
assert_contains "${body}" '"message":"local sync test"' "notify generic: payload has message"
assert_contains "${body}" '"host_type":"github"' "notify generic: payload has host_type"
assert_contains "${out}" "Webhook delivered" "notify generic: logs delivery (HTTP 200)"

# --- Slack-shaped payload (detected by URL substring) ------------------------
: > "${REQ_LOG}"
env GITPRESERVER_WEBHOOK_URL="http://127.0.0.1:${PORT}/hooks.slack.com/services/x" \
    GITPRESERVER_WEBHOOK_ALLOW_INSECURE="true" \
    bash "${NOTIFY_SH}" "success" "slack shape" >/dev/null 2>&1
assert_contains "$(last_body)" '"text":' "notify slack: payload uses Slack {text} shape"

# --- Discord-shaped payload --------------------------------------------------
: > "${REQ_LOG}"
env GITPRESERVER_WEBHOOK_URL="http://127.0.0.1:${PORT}/discord.com/api/webhooks/1/x" \
    GITPRESERVER_WEBHOOK_ALLOW_INSECURE="true" \
    bash "${NOTIFY_SH}" "failed" "discord shape" >/dev/null 2>&1
assert_contains "$(last_body)" '"embeds":' "notify discord: payload uses Discord {embeds} shape"

# --- WEBHOOK_ON=failure suppresses a success notification --------------------
: > "${REQ_LOG}"
out="$(env GITPRESERVER_WEBHOOK_URL="http://127.0.0.1:${PORT}/" \
    GITPRESERVER_WEBHOOK_ALLOW_INSECURE="true" \
    GITPRESERVER_WEBHOOK_ON="failure" \
    bash "${NOTIFY_SH}" "success" "should not send" 2>&1)"
rc=$?
assert_eq "${rc}" "0" "notify filter: exit 0"
assert_eq "$(req_count)" "0" "notify filter: success suppressed when WEBHOOK_ON=failure"

# --- insecure http rejected without opt-in ----------------------------------
: > "${REQ_LOG}"
out="$(env GITPRESERVER_WEBHOOK_URL="http://127.0.0.1:${PORT}/" \
    bash "${NOTIFY_SH}" "success" "no opt-in" 2>&1)"
rc=$?
assert_eq "${rc}" "0" "notify scheme: exit 0 (failure never breaks pipeline)"
assert_eq "$(req_count)" "0" "notify scheme: insecure http not delivered without opt-in"
assert_contains "${out}" "refusing insecure http" "notify scheme: warns about insecure http"

# --- unsupported scheme rejected --------------------------------------------
: > "${REQ_LOG}"
out="$(env GITPRESERVER_WEBHOOK_URL="ftp://example.com/hook" \
    bash "${NOTIFY_SH}" "success" "bad scheme" 2>&1)"
assert_eq "$(req_count)" "0" "notify scheme: ftp:// not delivered"
assert_contains "${out}" "unsupported scheme" "notify scheme: warns about unsupported scheme"

# --- multi-URL fan-out -------------------------------------------------------
: > "${REQ_LOG}"
env GITPRESERVER_WEBHOOK_URL="http://127.0.0.1:${PORT}/,http://127.0.0.1:${PORT}/" \
    GITPRESERVER_WEBHOOK_ALLOW_INSECURE="true" \
    bash "${NOTIFY_SH}" "success" "fan out" >/dev/null 2>&1
assert_eq "$(req_count)" "2" "notify fan-out: both URLs received a POST"

# --- empty webhook url is a no-op -------------------------------------------
: > "${REQ_LOG}"
env GITPRESERVER_WEBHOOK_URL="" bash "${NOTIFY_SH}" "success" "noop" >/dev/null 2>&1
rc=$?
assert_eq "${rc}" "0" "notify empty: exit 0"
assert_eq "$(req_count)" "0" "notify empty: nothing sent"

# ===========================================================================
section "Credentialed end-to-end (mirror / metadata / run-stages)"
# ===========================================================================

ENV_FILE="${GITPRESERVER_TEST_ENV:-${REPO_ROOT}/.env}"

# Read a single KEY from the .env WITHOUT sourcing it — a .env can contain
# arbitrary or malformed lines, and `source`-ing it would execute them. We only
# need the token and username, so extract them by name and strip surrounding
# quotes. Values already present in the environment win.
env_val() {
    local key="$1"
    [[ -f "${ENV_FILE}" ]] || return 0
    grep -E "^[[:space:]]*(export[[:space:]]+)?${key}=" "${ENV_FILE}" 2>/dev/null \
        | tail -1 | sed -E "s/^[[:space:]]*(export[[:space:]]+)?${key}=//" \
        | sed -E 's/^"(.*)"$/\1/; s/^'\''(.*)'\''$/\1/'
}
GP_TOKEN="${GITPRESERVER_TOKEN:-$(env_val GITPRESERVER_TOKEN)}"
GP_USER="${GITPRESERVER_USERNAME:-$(env_val GITPRESERVER_USERNAME)}"

# The full pipeline shells out to ghorg (mirror) and gh (metadata); without
# those binaries locally the run can't succeed regardless of credentials.
missing_e2e=""
[[ -n "${GP_TOKEN}" && -n "${GP_USER}" ]] || missing_e2e="credentials (GITPRESERVER_TOKEN + GITPRESERVER_USERNAME)"
command -v ghorg >/dev/null 2>&1 || missing_e2e="${missing_e2e:+${missing_e2e}, }ghorg"
command -v gh   >/dev/null 2>&1 || missing_e2e="${missing_e2e:+${missing_e2e}, }gh"

if [[ -n "${missing_e2e}" ]]; then
    skip "run-stages.sh full pipeline — missing: ${missing_e2e}"
    printf '       %sThe sync + notify suites above cover local behavior. The full mirror→metadata→sync\n       pipeline needs ghorg + gh + creds; run this inside the container image or a host with\n       those tools and a .env to exercise it end-to-end.%s\n' "${C_DIM}" "${C_RESET}"
else
    B="${WS}/b_e2e"
    mkdir -p "${B}"
    # Run the real pipeline; scripts call each other by bare name, so put them on PATH.
    out="$(env PATH="${BACKUP_DIR_SCRIPTS}:${PATH}" \
        GITPRESERVER_TOKEN="${GP_TOKEN}" \
        GITPRESERVER_USERNAME="${GP_USER}" \
        GITPRESERVER_BACKUP_DIR="${B}" \
        GITPRESERVER_RCLONE_REMOTE="d1" \
        GITPRESERVER_RETENTION_DAYS="0" \
        GITPRESERVER_STATUS_FILE="${B}/status.json" \
        bash "${RUN_STAGES_SH}" 2>&1)"
    rc=$?
    assert_eq "${rc}" "0" "run-stages: full pipeline exit 0"
    assert_contains "${out}" "All stages complete." "run-stages: reports completion"
    assert_file_exists "${B}/status.json" "run-stages: writes status file"
    status="$(jq -r '.status' "${B}/status.json" 2>/dev/null)"
    assert_eq "${status}" "success" "run-stages: status file reports success"
    if find "${DEST1}/gitpreserver-backups" -name '*.git' -maxdepth 4 -type d 2>/dev/null | grep -q .; then
        pass "run-stages: mirrored repo(s) synced to local destination"
    else
        fail "run-stages: mirrored repo(s) synced to local destination" "no .git dirs found under dest"
    fi
    rm -rf "${DEST1:?}/"* 2>/dev/null
fi

# ===========================================================================
section "Summary"
# ===========================================================================
TOTAL=$((PASS + FAIL))
printf '  %s%d passed%s, %s%d failed%s, %s%d skipped%s  (%d assertions run)\n' \
    "${C_GREEN}" "${PASS}" "${C_RESET}" \
    "${C_RED}" "${FAIL}" "${C_RESET}" \
    "${C_YELLOW}" "${SKIP}" "${C_RESET}" "${TOTAL}"

if (( FAIL > 0 )); then
    printf '\n  %sFailed:%s\n' "${C_RED}" "${C_RESET}"
    for n in "${FAILED_NAMES[@]}"; do printf '    - %s\n' "$n"; done
    exit 1
fi
printf '\n  %sAll good.%s\n' "${C_GREEN}" "${C_RESET}"
exit 0
