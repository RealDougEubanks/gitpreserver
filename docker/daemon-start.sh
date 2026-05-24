#!/usr/bin/env bash
#
# Daemon mode entry point. Starts the web UI and supercronic scheduler
# as sibling processes under tini. supercronic runs in the foreground
# (exec'd last) so tini tracks it as the main child; the web server runs
# as a background job and is reaped by tini when supercronic exits.

set -euo pipefail

log() { printf '[gitpreserver] %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }

SCHEDULE="${GITPRESERVER_SCHEDULE:-0 2 * * 0}"
WEB_PORT="${GITPRESERVER_WEB_PORT:-6033}"
STATUS_FILE="${GITPRESERVER_STATUS_FILE:-/tmp/gitpreserver-status.json}"

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

log "Daemon mode starting. Schedule: ${SCHEDULE}. Web UI: port ${WEB_PORT}."

# Start the web UI in the background; tini will reap it on exit.
python3 /usr/local/bin/webserver.py &

# supercronic in the foreground — tini tracks this as the main child.
exec supercronic /tmp/gitpreserver.cron
