#!/usr/bin/env bash
#
# Build the GitPreserver Synology SPK package.
#
# An SPK is a tar archive containing:
#   INFO             — package metadata
#   package.tgz      — the package payload (what goes in /var/packages/<pkg>/target/)
#   scripts/         — lifecycle scripts (preinst, postinst, preuninst, start-stop-status)
#   WIZARD_UIFILES/  — install wizard JSON
#
# Usage:
#   ./synology/build-spk.sh [--version X.Y.Z-N]
#
# Output: synology/dist/gitpreserver-X.Y.Z-N.spk

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

log() { printf '[build-spk] %s\n' "$*"; }

# Read version from INFO
VERSION=$(grep '^version=' "${SCRIPT_DIR}/INFO" | cut -d'"' -f2)

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 2 ;;
    esac
done

# ---------------------------------------------------------------------------
# Guard: the INFO version must match the latest CHANGELOG release so the SPK
# version can't silently drift from the released version again. We compare the
# x.y.z part of the Synology version (x.y.z-N) against the top-most
# "## [x.y.z]" heading in CHANGELOG.md (ignoring an "Unreleased" section).
# ---------------------------------------------------------------------------
CHANGELOG="${REPO_ROOT}/CHANGELOG.md"
if [[ -f "${CHANGELOG}" ]]; then
    CHANGELOG_VERSION=$(grep -Eo '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' "${CHANGELOG}" \
        | head -n 1 | sed -E 's/^## \[([0-9]+\.[0-9]+\.[0-9]+)\].*/\1/')
    INFO_VERSION="${VERSION%%-*}"
    if [[ -z "${CHANGELOG_VERSION}" ]]; then
        echo "ERROR: could not parse a version from ${CHANGELOG}" >&2
        exit 1
    fi
    if [[ "${INFO_VERSION}" != "${CHANGELOG_VERSION}" ]]; then
        echo "ERROR: version mismatch — INFO is '${INFO_VERSION}' (from '${VERSION}')" >&2
        echo "       but CHANGELOG.md latest release is '${CHANGELOG_VERSION}'." >&2
        echo "       Update synology/INFO 'version' to match the released version." >&2
        exit 1
    fi
    log "Version check passed: INFO ${INFO_VERSION} matches CHANGELOG ${CHANGELOG_VERSION}"
else
    echo "ERROR: CHANGELOG.md not found at ${CHANGELOG}; cannot verify version." >&2
    exit 1
fi

DIST_DIR="${SCRIPT_DIR}/dist"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "${WORK_DIR}"' EXIT

mkdir -p "${DIST_DIR}"

log "Building GitPreserver SPK v${VERSION}"

# ---------------------------------------------------------------------------
# 1. Build package.tgz — the payload installed to /var/packages/gitpreserver/target/
# ---------------------------------------------------------------------------
PKG_WORK="${WORK_DIR}/package"
mkdir -p "${PKG_WORK}"

# The run-backup.sh wrapper lives in target/
install -m 0755 "${SCRIPT_DIR}/target/run-backup.sh" "${PKG_WORK}/run-backup.sh"

# A minimal .env.example so users know what to configure post-install
install -m 0644 "${REPO_ROOT}/config/.env.example" "${PKG_WORK}/.env.example"

# rclone.conf.example
install -m 0644 "${REPO_ROOT}/rclone/rclone.conf.example" "${PKG_WORK}/rclone.conf.example"

tar -czf "${WORK_DIR}/package.tgz" -C "${PKG_WORK}" .

# ---------------------------------------------------------------------------
# 2. Assemble the SPK staging directory
# ---------------------------------------------------------------------------
SPK_STAGE="${WORK_DIR}/spk"
mkdir -p "${SPK_STAGE}/scripts" "${SPK_STAGE}/WIZARD_UIFILES" "${SPK_STAGE}/conf"

cp "${SCRIPT_DIR}/INFO"                          "${SPK_STAGE}/INFO"
cp "${WORK_DIR}/package.tgz"                     "${SPK_STAGE}/package.tgz"
cp "${SCRIPT_DIR}/scripts/preinst"               "${SPK_STAGE}/scripts/preinst"
cp "${SCRIPT_DIR}/scripts/postinst"              "${SPK_STAGE}/scripts/postinst"
cp "${SCRIPT_DIR}/scripts/preuninst"             "${SPK_STAGE}/scripts/preuninst"
cp "${SCRIPT_DIR}/scripts/start-stop-status"     "${SPK_STAGE}/scripts/start-stop-status"
cp "${SCRIPT_DIR}/WIZARD_UIFILES/install_uifile" "${SPK_STAGE}/WIZARD_UIFILES/install_uifile"
cp "${SCRIPT_DIR}/conf/resource"                 "${SPK_STAGE}/conf/resource"

chmod +x \
    "${SPK_STAGE}/scripts/preinst" \
    "${SPK_STAGE}/scripts/postinst" \
    "${SPK_STAGE}/scripts/preuninst" \
    "${SPK_STAGE}/scripts/start-stop-status"

# ---------------------------------------------------------------------------
# 3. Pack the SPK
# ---------------------------------------------------------------------------
SPK_NAME="gitpreserver-${VERSION}.spk"
SPK_PATH="${DIST_DIR}/${SPK_NAME}"

tar -cf "${SPK_PATH}" -C "${SPK_STAGE}" .

log "Built: ${SPK_PATH}"
log "Install via: DSM → Package Center → Manual Install"
