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
#   GITPRESERVER_WEBHOOK_ALLOW_INSECURE
#                              Set to "true" to permit http:// webhook URLs (e.g. a
#                              LAN ntfy instance). Defaults to false: only https:// is
#                              accepted. Plain http exposes payloads in transit, so this
#                              is an explicit, documented opt-in.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"

STATUS="${1:?notify.sh requires a status argument (success|failed)}"
MESSAGE="${2:?notify.sh requires a message argument}"
WEBHOOK_URLS="${GITPRESERVER_WEBHOOK_URL:-}"
WEBHOOK_ON="${GITPRESERVER_WEBHOOK_ON:-always}"
ALLOW_INSECURE="${GITPRESERVER_WEBHOOK_ALLOW_INSECURE:-false}"

if [[ -z "${WEBHOOK_URLS}" ]]; then
    exit 0
fi

# Determine whether to fire based on WEBHOOK_ON.
case "${WEBHOOK_ON}" in
    always)  ;;
    success) [[ "${STATUS}" == "success" ]] || exit 0 ;;
    failure) [[ "${STATUS}" == "failed"  ]] || exit 0 ;;
    *)
        log_warn "WARNING: unknown GITPRESERVER_WEBHOOK_ON value '${WEBHOOK_ON}'. Using 'always'."
        ;;
esac

TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
USERNAME="${GITPRESERVER_USERNAME:-unknown}"
HOST_TYPE="${GITPRESERVER_HOST_TYPE:-github}"

# Build the payload for each URL based on the destination service.
# Slack: {"text": "..."} — detected by hooks.slack.com in the URL
# Discord: {"content": "..."} — detected by discord.com/api/webhooks
# Generic: {"status":"...","message":"...","timestamp":"...","host":"...","username":"..."}

# Accept https:// always; accept http:// only with the explicit opt-in.
# Reject every other scheme (ftp://, file://, bare strings, URLs starting
# with '-', etc.) so we never hand an attacker-controlled value to curl.
url_is_allowed() {
    local url="$1"
    if [[ "${url}" == https://* ]]; then
        return 0
    fi
    if [[ "${url}" == http://* ]]; then
        if [[ "${ALLOW_INSECURE}" == "true" ]]; then
            return 0
        fi
        log_warn "WARNING: refusing insecure http:// webhook URL (set GITPRESERVER_WEBHOOK_ALLOW_INSECURE=true to permit): ${url%%\?*}"
        return 1
    fi
    log_warn "WARNING: rejecting webhook URL with unsupported scheme: ${url%%\?*}"
    return 1
}

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

    # A webhook delivery failure must NEVER fail the backup pipeline. curl's
    # exit status (incl. -f for HTTP 4xx/5xx) is captured and logged as a
    # WARNING only. --max-time bounds the call; --retry handles transient
    # failures with backoff. '--' guards against a URL starting with '-'.
    local http_code
    if http_code=$(curl -fsSL \
            -o /dev/null \
            -w '%{http_code}' \
            --max-time 15 \
            --retry 2 \
            --retry-delay 3 \
            -X POST \
            -H "Content-Type: application/json" \
            -d "${payload}" \
            -- "${url}" \
            2>/dev/null); then
        log_info "Webhook delivered to ${url%%\?*} (HTTP ${http_code})"
    else
        log_warn "WARNING: webhook delivery failed for ${url%%\?*} (HTTP ${http_code:-000})"
    fi
}

# Split comma-separated URLs and send to each.
IFS=',' read -ra url_list <<< "${WEBHOOK_URLS}"
for url in "${url_list[@]}"; do
    url="${url#"${url%%[![:space:]]*}"}"  # trim leading whitespace
    url="${url%"${url##*[![:space:]]}"}"  # trim trailing whitespace
    [[ -z "${url}" ]] && continue
    url_is_allowed "${url}" || continue
    send_webhook "${url}"
done
