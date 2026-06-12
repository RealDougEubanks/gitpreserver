#!/usr/bin/env bash
#
# Daemon mode entry point. Starts the web UI and supercronic scheduler
# as sibling processes under tini. supercronic runs in the foreground
# (exec'd last) so tini tracks it as the main child; the web server runs
# as a background job and is reaped by tini when supercronic exits.

set -euo pipefail

# Locate the shared logging helper. In the container the docker scripts and
# backup scripts both land in /usr/local/bin, so lib/ sits beside this file;
# in the source tree the lib lives under backup/lib. Try both.
_gp_dir="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck disable=SC2034  # consumed by the sourced lib/log.sh, not in this file
GITPRESERVER_LOG_COMPONENT="daemon"
if [[ -f "${_gp_dir}/lib/log.sh" ]]; then
    source "${_gp_dir}/lib/log.sh"
else
    source "${_gp_dir}/../backup/lib/log.sh"
fi

SCHEDULE="${GITPRESERVER_SCHEDULE:-0 2 * * 0}"
WEB_PORT="${GITPRESERVER_WEB_PORT:-6033}"
STATUS_FILE="${GITPRESERVER_STATUS_FILE:-/tmp/gitpreserver-status.json}"

# Validate the schedule before it is interpolated into the crontab line.
# GITPRESERVER_SCHEDULE is attacker-controllable; without validation a value
# like "* * * * * cmd; evil" would inject an arbitrary command into the
# crontab that supercronic runs as the gitpreserver user.
#
# Accepted forms:
#   - A supercronic named shortcut: @yearly @annually @monthly @weekly
#     @daily @midnight @hourly  (a single token, no command can follow).
#   - A standard 5-field expression. Each field may only contain digits and
#     the cron operators * , / - so no shell metacharacters survive. Fields
#     are separated by runs of spaces/tabs; exactly five fields are allowed,
#     which prevents a trailing injected command from being treated as a 6th
#     field.
validate_schedule() {
    local sched="$1"
    # Named shortcuts: whole value must be exactly one of these tokens.
    if [[ "${sched}" =~ ^@(yearly|annually|monthly|weekly|daily|midnight|hourly)$ ]]; then
        return 0
    fi
    # 5-field form: ^field( field){4}$ where field is [0-9*,/-]+
    local field='[0-9*,/-]+'
    if [[ "${sched}" =~ ^${field}([[:space:]]+${field}){4}$ ]]; then
        return 0
    fi
    return 1
}

if ! validate_schedule "${SCHEDULE}"; then
    log_error "ERROR: GITPRESERVER_SCHEDULE is not a valid cron expression: '${SCHEDULE}'"
    log_error "Expected a 5-field cron expression (e.g. '0 2 * * 0') or a shortcut like @daily."
    exit 1
fi

# Write initial idle status if no status file exists yet.
if [[ ! -f "${STATUS_FILE}" ]]; then
    jq -cn \
        --arg sched "${SCHEDULE}" \
        '{status:"idle", last_run:null, message:"Waiting for first scheduled run.", schedule:$sched}' \
        > "${STATUS_FILE}"
fi

# Build the crontab supercronic will read. flock prevents overlapping runs.
printf '%s flock -n /tmp/gitpreserver.lock run-stages.sh\n' "${SCHEDULE}" \
    > /tmp/gitpreserver.cron

log_info "Daemon mode starting. Schedule: ${SCHEDULE}. Web UI: port ${WEB_PORT}."

# Start the web UI in the background; tini will reap it on exit.
python3 /usr/local/bin/webserver.py &

# supercronic in the foreground — tini tracks this as the main child.
exec supercronic /tmp/gitpreserver.cron
