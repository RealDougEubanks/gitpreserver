#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

log() { echo "[gitpreserver] $(date +%Y-%m-%dT%H:%M:%S) $*"; }

log "Starting backup run"

docker compose run --rm mirror
docker compose run --rm metadata
docker compose run --rm sync

log "Backup run complete"
