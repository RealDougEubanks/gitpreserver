# Shared bats test helpers.
#
# Each test gets a fresh BATS_TEST_TMPDIR (provided by bats-core >= 1.5).
# We set GITPRESERVER_BACKUP_DIR there and clear any GITPRESERVER_* env
# vars that may have leaked in from the shell so tests are reproducible.

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export REPO_ROOT

    # Clear inherited env so the host environment can't influence assertions.
    unset GITPRESERVER_TOKEN GITPRESERVER_USERNAME GITPRESERVER_HOST_TYPE \
          GITPRESERVER_HOST_URL GITPRESERVER_DRY_RUN GITPRESERVER_BACKUP_DIR \
          GITPRESERVER_RCLONE_REMOTE GITPRESERVER_RCLONE_PATH \
          GITPRESERVER_RCLONE_TRANSFERS GITPRESERVER_ENCRYPT \
          GITPRESERVER_CRYPT_REMOTE GITPRESERVER_RETENTION_DAYS \
          GITPRESERVER_LOG_LEVEL GITPRESERVER_CONCURRENCY

    export GITPRESERVER_BACKUP_DIR="${BATS_TEST_TMPDIR}/backups"
    mkdir -p "${GITPRESERVER_BACKUP_DIR}"
}
