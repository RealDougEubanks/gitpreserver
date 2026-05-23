# Changelog

All notable changes to GitPreserver are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
This project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added
- `GITPRESERVER_MODE=daemon` — keeps the container running permanently, fires backups on an internal cron schedule via `supercronic`, and serves a web UI on port 6033
- `docker/daemon-start.sh` — daemon entry point: writes initial status, builds the supercronic crontab, starts the web server, and exec's supercronic under tini
- `docker/webserver.py` — stdlib-only Python 3 web server (no pip dependencies). Routes: `GET /` dashboard, `GET /healthz` JSON health check, `GET /config` redacted config, `POST /run` manual trigger
- `backup/run-stages.sh` now writes a JSON status file (`GITPRESERVER_STATUS_FILE`, default `/tmp/gitpreserver-status.json`) after each stage and on failure, giving the web UI real-time feedback
- `supercronic` added to the Docker image as the in-container cron scheduler for daemon mode
- `python3` added to the Docker image for the web server
- `GITPRESERVER_WEB_PORT` (default `6033`) controls the web UI port in daemon mode
- `GITPRESERVER_STATUS_FILE` allows overriding the status JSON path
- `daemon` service in `docker-compose.yml` with `restart: unless-stopped` and port mapping
- `docs/daemon-mode.md` — full guide covering run modes, web UI routes, schedule syntax, rclone env-var configuration, and security notes
- rclone remote configuration via `RCLONE_CONFIG_<REMOTE>_<KEY>=value` environment variables — `rclone.conf` is no longer required
- rclone env-var examples added to `config/.env.example`

### Changed
- `docker-compose.yml` `sync` and `daemon` services now fall back to mounting `/dev/null` when `GITPRESERVER_RCLONE_CONFIG` is not set, allowing env-var-only rclone configuration without a config file on disk
- `docker/entrypoint.sh` now reads `GITPRESERVER_MODE` and forks to `daemon-start.sh` when set to `daemon`, otherwise passes through to the original `"$@"` path (`oneshot` behaviour unchanged)

### Added
- `backup/run-stages.sh` — in-container orchestrator that runs mirror → metadata → sync sequentially in a single container. Used by unRAID, Synology Container Manager, and plain `docker run`. `docker-compose` is unaffected (its per-service `command:` entries still apply).
- `docker/entrypoint.sh` — runtime PUID/PGID/UMASK handler. Container starts as root, adjusts the `gitpreserver` user to match host UID/GID, chowns writable mounts, and drops privileges via `gosu`. Workload never runs as root.
- `unraid/gitpreserver.xml` — Community Applications template, audited end-to-end against the v1.0 codebase (fine-grained PAT guidance, correct rclone path, PUID/PGID/UMASK exposed, misleading `GITPRESERVER_SCHEDULE` removed).
- `docs/unraid-setup.md` — rewritten install guide covering the CA template flow and a manual `docker compose` flow, with User Scripts scheduling examples for both.
- `CREDITS.md` attributing every bundled runtime tool (ghorg, gh, rclone, tini, jq, git, Debian) and every dev/CI tool (bats-core, ShellCheck, hadolint, gitleaks) with project links, licenses, and the role each plays in GitPreserver
- README "Credits" section linking to `CREDITS.md`
- Dockerfile labels `org.opencontainers.image.documentation`, `org.opencontainers.image.vendor`, and `org.gitpreserver.dependencies` so Docker Hub and SBOM tools display the bundled-tool inventory with versions

---

## [1.0.0] — 2026-05-21

### Added
- Initial project scaffold: Dockerfile, backup scripts, docker-compose, config examples
- `backup/mirror.sh` — mirror-clone all repos for a GitHub account via ghorg
- `backup/metadata.sh` — export issues, pull requests, and releases as JSON sidecars
- `backup/sync.sh` — rclone sync to any configured remote, with rclone crypt support
- `run-backup.sh` — single-command wrapper to run all three stages in sequence
- `config/.env.example` — fully commented environment variable reference
- `config/gitpreserver.conf.example` — optional INI-style config file format
- `docker/Dockerfile` — single image containing ghorg, gh CLI, and rclone
- `docker-compose.yml` — three-service orchestration with dependency ordering
- `rclone/rclone.conf.example` — annotated remote templates for B2, S3, MEGA, Drive, SMB
- `cron/crontab.example` — ready-to-use cron entry
- GitHub Actions: shellcheck lint on push, multi-arch Docker release on tag
- Synology DSM 7+ SPK package scaffolding
- unRAID Community Applications Docker template
- Full documentation suite (setup, configuration, encryption, storage backends, restoring)
- Local snapshot retention pruning via `GITPRESERVER_RETENTION_DAYS`
- Dry-run mode via `GITPRESERVER_DRY_RUN=true`
- `docs/assumptions.md` capturing non-obvious design decisions per the project Golden Rules
- `bats` test suite under `tests/` covering input validation and dry-run pipelines
- CI: hadolint on the Dockerfile, `docker compose build` smoke job, bats run, gitleaks secret scan
- `run-backup.sh` now accepts a positional destination path, `--no-sync`, and `--dry-run` flags so a single command can run an ad-hoc local backup (`./run-backup.sh /mnt/nas/github --no-sync`) without editing `.env`
- Documentation now leads with GitHub fine-grained PATs (`github_pat_…`) and the per-repository least-privilege permissions model; classic PATs (`ghp_…`) are retained as a documented fallback
- `GITPRESERVER_HOST_BACKUP_DIR` separates the host bind-mount path from the in-container `GITPRESERVER_BACKUP_DIR`, fixing a path-overload bug that prevented runs on macOS

### Changed
- Container now runs as the non-root `gitpreserver` user (UID/GID 1000, overridable via `PUID`/`PGID`)
- `cap_drop: ALL` and `no-new-privileges:true` applied to all compose services
- `rclone.conf` is now mounted at `/home/gitpreserver/.config/rclone/rclone.conf` (set via `RCLONE_CONFIG`); previously `/root/.config/rclone/rclone.conf`
- Tokens are passed to `ghorg`/`gh` exclusively via env vars (`GHORG_*_TOKEN`, `GH_TOKEN`); the previous `--token=` CLI flag exposed credentials in `ps`/`/proc`
- All log timestamps are now UTC (`YYYY-MM-DDTHH:MM:SSZ`)
- `run-backup.sh` now self-execs under `flock -n` to prevent overlapping cron runs

### Fixed
- `backup/mirror.sh` now uses ghorg's `--path` (absolute parent) flag with `--output-dir=repos`; the previous code passed an absolute path to `--output-dir`, which ghorg treats as a literal subdirectory name under `$HOME/ghorg/`, so cloned repos never reached the bind-mounted `/backups` volume
- `backup/metadata.sh` now exports via `gh api --paginate | jq -s 'add // []'`; the previous `gh release list`/`gh issue list`/`gh pr list` subcommands exit non-zero on empty result sets, which produced a false-positive `WARNING: could not export releases` for every repo. `issues.json` no longer contains PRs (the `/issues` endpoint returns both — filtered out via `select(.pull_request == null)`)
- `run-backup.sh` now honors `GITPRESERVER_DRY_RUN=true` set in the shell environment, not just the `--dry-run` CLI flag; previously the shell var was silently dropped because `docker compose run` does not inherit parent-shell env into container env
- ghorg release asset URL — release files use `Linux` (capital L) and the `arm64` arch suffix; the previous URL would 404 on both amd64 and arm64
- `backup/metadata.sh` reported "1 repository" when the user had zero (`echo` on an empty string still emits a newline); now uses `mapfile` and an array length
- `backup/sync.sh` retention pruning: removed dead `${DRY_RUN:+}` token and switched to `find -print0` / `read -d ''` so unusual directory names cannot break `rm`

### Security
- Input validation on `GITPRESERVER_USERNAME` and discovered repo names (`^[A-Za-z0-9._-]+$`)
- Numeric validation on `GITPRESERVER_RETENTION_DAYS` and `GITPRESERVER_RCLONE_TRANSFERS`
- `.dockerignore` prevents `.env`, `rclone.conf`, `.git/`, docs, and CI configs from entering the image build context

First public release. GitHub account backup (Phase 1).

[Unreleased]: https://github.com/dougeubanks/gitpreserver/compare/HEAD...HEAD
