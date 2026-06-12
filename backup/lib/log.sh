# shellcheck shell=bash
#
# Shared structured-logging helper for GitPreserver bash scripts.
#
# Emits logfmt records to stderr, one per line:
#
#   ts=2026-06-11T12:00:00Z level=info component=mirror run_id=abc123 msg="…"
#
# Fields:
#   ts        UTC ISO-8601 timestamp (YYYY-MM-DDTHH:MM:SSZ) — the format the
#             rest of the project already standardised on.
#   level     info | warn | error  (set by the wrapper used)
#   component the script that emitted the line (basename minus .sh)
#   run_id    a per-process correlation id, stable for the life of the process
#             and inherited by child stages via the GITPRESERVER_RUN_ID env var.
#   msg       the human-readable message, always double-quoted with embedded
#             quotes and backslashes escaped so a hostile message can never
#             inject extra logfmt fields or break the line.
#
# Source this file once near the top of a script:
#
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"
#
# then call log_info / log_warn / log_error with the message text.

# Component name: caller may set GITPRESERVER_LOG_COMPONENT before sourcing;
# otherwise derive it from the sourcing script's name. Falls back to "gitpreserver".
if [[ -z "${GITPRESERVER_LOG_COMPONENT:-}" ]]; then
    if [[ -n "${BASH_SOURCE[1]:-}" ]]; then
        _gp_src="${BASH_SOURCE[1]##*/}"
        GITPRESERVER_LOG_COMPONENT="${_gp_src%.sh}"
        unset _gp_src
    else
        GITPRESERVER_LOG_COMPONENT="gitpreserver"
    fi
fi

# Correlation id. Reuse one threaded in from a parent process (run-stages.sh
# exports it so mirror/metadata/sync/notify all share a single id). Otherwise
# derive a stable per-process id from the date and the PID — cheap, requires no
# extra tooling, and is unique enough to correlate a single run's lines.
if [[ -z "${GITPRESERVER_RUN_ID:-}" ]]; then
    GITPRESERVER_RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
    export GITPRESERVER_RUN_ID
fi

# Escape a value for safe inclusion inside a double-quoted logfmt field.
# Backslashes first (so we don't double-escape the quotes we add next), then
# double quotes, then fold newlines/tabs/carriage returns into spaces so a
# multi-line message can never spill onto fake extra log lines.
_gp_log_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/ }"
    s="${s//$'\r'/ }"
    s="${s//$'\t'/ }"
    printf '%s' "${s}"
}

# Core emitter. Usage: log <level> <message...>
log() {
    local level="$1"; shift
    local msg="$*"
    printf 'ts=%s level=%s component=%s run_id=%s msg="%s"\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        "${level}" \
        "${GITPRESERVER_LOG_COMPONENT}" \
        "${GITPRESERVER_RUN_ID}" \
        "$(_gp_log_escape "${msg}")" \
        >&2
}

log_info()  { log info "$@"; }
log_warn()  { log warn "$@"; }
log_error() { log error "$@"; }
