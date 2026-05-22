#!/usr/bin/env bash
#
# GitPreserver runtime entrypoint.
#
# The container starts as root for a few hundred milliseconds so it can:
#   1. Adjust the gitpreserver user's UID/GID to match host PUID/PGID
#      (lets unRAID/Synology bind mounts work without manual chown).
#   2. chown any writable mounts so the dropped-privilege user can write.
#   3. Apply UMASK if requested.
# Then execs the workload via gosu as the unprivileged gitpreserver user.
#
# This is the linuxserver.io / lscr.io pattern, narrowed to the few caps
# we actually need (CHOWN, SETUID, SETGID).

set -euo pipefail

log() { printf '[gitpreserver] %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }

PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

if ! [[ "${PUID}" =~ ^[0-9]+$ && "${PGID}" =~ ^[0-9]+$ ]]; then
    log "ERROR: PUID and PGID must be integers (got PUID='${PUID}', PGID='${PGID}')."
    exit 1
fi

current_uid="$(id -u gitpreserver)"
current_gid="$(id -g gitpreserver)"

if [[ "${PGID}" != "${current_gid}" ]]; then
    groupmod -o -g "${PGID}" gitpreserver
fi
if [[ "${PUID}" != "${current_uid}" ]]; then
    usermod -o -u "${PUID}" gitpreserver
fi

# Re-chown writable mounts so the (possibly renumbered) user can write.
# Only the staged backup dir and the user's home need it; rclone.conf is
# mounted read-only and stays owned by the host user.
chown -R "${PUID}:${PGID}" /backups /home/gitpreserver 2>/dev/null || true

if [[ -n "${UMASK:-}" ]]; then
    if ! [[ "${UMASK}" =~ ^[0-7]{3,4}$ ]]; then
        log "ERROR: UMASK must be a 3- or 4-digit octal value (got '${UMASK}')."
        exit 1
    fi
    umask "${UMASK}"
fi

exec gosu gitpreserver:gitpreserver "$@"
