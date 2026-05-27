#!/usr/bin/env bash
#
# Send a webhook notification for a completed or failed backup run.
#
# Usage (called internally by run-stages.sh):
#   notify.sh <status> <message>
#
# Env vars:
#   GITPRESERVER_WEBHOOK_URL   Comma-separated list of webhook URLs to POST to.
#                              Leave unset or empty to skip notifications.
#   GITPRESERVER_WEBHOOK_ON    When to fire: always | success | failure (default: always)

set -euo pipefail

log() { printf '[gitpreserver] %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }

STATUS="${1:?notify.sh requires a status argument (success|failed)}"
MESSAGE="${2:?notify.sh requires a message argument}"
WEBHOOK_URLS="${GITPRESERVER_WEBHOOK_URL:-}"
WEBHOOK_ON="${GITPRESERVER_WEBHOOK_ON:-always}"

if [[ -z "${WEBHOOK_URLS}" ]]; then
    exit 0
fi

# Determine whether to fire based on WEBHOOK_ON.
case "${WEBHOOK_ON}" in
    always)  ;;
    success) [[ "${STATUS}" == "success" ]] || exit 0 ;;
    failure) [[ "${STATUS}" == "failed"  ]] || exit 0 ;;
    *)
        log "WARNING: unknown GITPRESERVER_WEBHOOK_ON value '${WEBHOOK_ON}'. Using 'always'."
        ;;
esac

TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
USERNAME="${GITPRESERVER_USERNAME:-unknown}"
HOST_TYPE="${GITPRESERVER_HOST_TYPE:-github}"

# Build the payload for each URL based on the destination service.
# Slack: {"text": "..."} — detected by hooks.slack.com in the URL
# Discord: {"content": "..."} — detected by discord.com/api/webhooks
# Generic: {"status":"...","message":"...","timestamp":"...","host":"...","username":"..."}

send_webhook() {
    local url="$1"
    local payload

    if [[ "${url}" == *"hooks.slack.com"* ]]; then
        local icon=":white_check_mark:"
        [[ "${STATUS}" == "failed" ]] && icon=":x:"
        payload=$(jq -cn \
            --arg icon "${icon}" \
            --arg status "${STATUS}" \
            --arg msg "${MESSAGE}" \
            --arg user "${USERNAME}" \
            --arg host "${HOST_TYPE}" \
            --arg ts "${TIMESTAMP}" \
            '{"text": "\($icon) GitPreserver backup \($status) — \($host)/\($user)\n\($msg)\n\($ts)"}')

    elif [[ "${url}" == *"discord.com/api/webhooks"* ]]; then
        local color=3066993  # green
        [[ "${STATUS}" == "failed" ]] && color=15158332  # red
        payload=$(jq -cn \
            --arg status "${STATUS}" \
            --arg msg "${MESSAGE}" \
            --arg user "${USERNAME}" \
            --arg host "${HOST_TYPE}" \
            --arg ts "${TIMESTAMP}" \
            --argjson color "${color}" \
            '{"embeds":[{
                "title": ("GitPreserver backup " + $status),
                "description": ($msg + "\n**Host:** " + $host + "/" + $user),
                "color": $color,
                "footer": {"text": $ts}
            }]}')

    else
        # Generic JSON — works with any HTTP endpoint, ntfy.sh, Make, Zapier, etc.
        payload=$(jq -cn \
            --arg status "${STATUS}" \
            --arg msg "${MESSAGE}" \
            --arg user "${USERNAME}" \
            --arg host "${HOST_TYPE}" \
            --arg ts "${TIMESTAMP}" \
            '{"status":$status,"message":$msg,"username":$user,"host_type":$host,"timestamp":$ts}')
    fi

    if ! curl -fsSL \
            -X POST \
            -H "Content-Type: application/json" \
            -d "${payload}" \
            "${url}" \
            > /dev/null 2>&1; then
        log "WARNING: webhook delivery failed for ${url%%\?*}"
    else
        log "Webhook delivered to ${url%%\?*}"
    fi
}

# Split comma-separated URLs and send to each.
IFS=',' read -ra url_list <<< "${WEBHOOK_URLS}"
for url in "${url_list[@]}"; do
    url="${url#"${url%%[![:space:]]*}"}"  # trim leading whitespace
    url="${url%"${url##*[![:space:]]}"}"  # trim trailing whitespace
    [[ -z "${url}" ]] && continue
    send_webhook "${url}"
done
