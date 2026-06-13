# Changelog

All notable changes to GitPreserver are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
This project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Fixed
- `run-backup.sh` no longer passes an unconditional `--quiet` to `docker compose build`. Older Docker/Compose releases reject that flag (`unknown flag: --quiet`) and the run aborted before any stage executed; the script now probes for support and falls back to a normal build.

---

## [2.1.0] — 2026-06-13

### Added
- Webhook notifications (`backup/notify.sh`). `GITPRESERVER_WEBHOOK_URL` takes one or more URLs (comma-separated); the payload is shaped per destination — Slack (`{text}`), Discord (`{embeds}`), or generic JSON for anything else (ntfy, Make, Zapier). `GITPRESERVER_WEBHOOK_ON` controls when to fire: `always` (default) | `success` | `failure`. Delivery has a 15s timeout and retries; a failed notification logs a warning and never fails the backup.
- Multiple rclone destinations. `GITPRESERVER_RCLONE_REMOTE` accepts a comma-separated list; each remote is synced independently. With encryption enabled, `GITPRESERVER_CRYPT_REMOTE` takes a matching list that pairs to the plain remotes by position.
- Web UI authentication. `GITPRESERVER_WEB_TOKEN` is a bearer token required for `POST /run` and `GET /config` (auto-generated and printed to stderr if unset). `GITPRESERVER_WEB_BIND` sets the listen interface.
- `GITPRESERVER_WEBHOOK_ALLOW_INSECURE` permits plain `http://` webhook URLs (for a LAN ntfy instance); https is required otherwise.
- `tests/local-sync-test.sh` — local integration harness that drives the real sync and notify scripts (no mocks) against rclone's local backend and a throwaway HTTP server.
- CI: Trivy image vulnerability scan with a documented `.trivyignore` policy; `.github/dependabot.yml` for github-actions and docker updates; GitHub Release creation and Docker Hub description sync on tag push.
- Dockerfile `HEALTHCHECK` probing `/healthz` (meaningful in daemon mode).

### Changed
- Structured logging. All bash scripts now emit logfmt records (`ts level component run_id msg`) to **stderr** via a shared `backup/lib/log.sh`, replacing plain-text lines on stdout. Anything parsing the previous log format will need to adapt.
- `backup/sync.sh` no longer aborts on the first failing remote. Each remote syncs independently, local retention pruning always runs, the run exits non-zero if any remote failed, and the failed-remote list is written to `<backup_dir>/.gitpreserver-failed-remotes` for the notification layer.
- Dockerfile is now a multi-stage build (curl/unzip stay in the builder and are dropped from the runtime image). Bundled tools bumped and pinned with verified per-architecture SHA256 checksums: ghorg 1.11.11, gh 2.94.0, rclone 1.74.3, supercronic 0.2.46.
- `synology/INFO` version bumped to `2.1.0-1`; the Docker image tag is derived from INFO so it stays in sync, and `build-spk.sh` fails if INFO and the changelog disagree.

### Security
- The daemon web server's `POST /run` now requires the bearer token plus an `Origin` check and a request-body size limit. Previously it was unauthenticated and CSRF-able while bound to all interfaces.
- Webhook URLs are redacted on the `/config` endpoint and dashboard (Slack/Discord webhook URLs are themselves credentials).
- Bitbucket credentials are passed to curl via a `0600` `--config` file instead of `-u user:token` on the command line, keeping them out of the process list.
- `GITPRESERVER_SCHEDULE` is validated against a strict cron grammar before being written to the supercronic crontab, preventing command injection.
- `GITPRESERVER_HOST_URL` is validated as a well-formed http(s) URL before use.

### Fixed
- `backup/metadata.sh` no longer writes a complete-looking `issues.json`/`pull_requests.json` when pagination fails mid-way — the partial result is written with a `.partial` suffix and the stage exits non-zero. HTTP calls now have timeouts.
- unRAID template `<Icon>` pointed at a non-existent `assets/icon.png`; now uses an existing asset. Synology `INFO` had dead GitHub URLs (wrong org); corrected to `RealDougEubanks`.

---

## [2.0.0] — 2026-05-27

### Added
- Bitbucket metadata export — issues, pull requests (via REST API 2.0, basic auth with app password). Bitbucket has no releases API; `releases.json` is written as `[]` for consistency.
- GitLab metadata export — issues, merge requests, releases (via API v4, `PRIVATE-TOKEN` header, Link-header pagination). Works with gitlab.com and self-hosted instances via `GITPRESERVER_HOST_URL`.
- `GITPRESERVER_HOST_TYPE` — selects the git host: `github` (default) | `bitbucket` | `gitlab` | `gitea`. Previously only `github` ran metadata export; all others logged "not yet implemented". Gitea metadata remains Phase 3.
- `GITPRESERVER_HOST_URL` — base URL for self-hosted GitLab or Gitea (e.g. `https://gitlab.mycompany.com`). Ignored for hosted services.
- Synology SPK package is now buildable from source: run `./synology/build-spk.sh` to produce an installable `.spk`. Install via DSM Package Center → Manual Install.
- `synology/target/run-backup.sh` — DSM Task Scheduler wrapper that reads `.env` and runs the Docker container with flock overlap protection.
- `synology/scripts/preuninst` — removes the Task Scheduler entry on package uninstall.
- `synology/build-spk.sh` — assembles the SPK tarball from source files.
- Synology install wizard now collects Git Host, Host URL, and token fields for all four host types.
- unRAID template adds `GITPRESERVER_HOST_TYPE` (always-visible, default `github`) and `GITPRESERVER_HOST_URL` (advanced) fields. Token description updated to document Bitbucket app passwords and GitLab personal access tokens.
- 7 new bats tests covering Bitbucket and GitLab metadata paths (48 total).

### Changed
- `synology/INFO` version bumped to `1.1.0-1`.
- `synology/scripts/postinst` now registers the Task Scheduler entry via `synoschedtask` instead of leaving a placeholder comment.
- `backup/metadata.sh` dispatch refactored: `github`, `bitbucket`, `gitlab` each have a dedicated function; unknown host types now exit non-zero instead of silently skipping.
- `docs/synology-setup.md` updated to describe the SPK build process and manual install flow.

---

## [1.1.0] — 2026-05-24

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
- `backup/run-stages.sh` — in-container orchestrator that runs mirror → metadata → sync sequentially in a single container. Used by unRAID, Synology Container Manager, and plain `docker run`.
- `docker/entrypoint.sh` — runtime PUID/PGID/UMASK handler. Container starts as root, adjusts the `gitpreserver` user to match host UID/GID, chowns writable mounts, and drops privileges via `gosu`. Workload never runs as root.
- `unraid/gitpreserver.xml` — Community Applications template updated with daemon mode fields: Mode, Schedule, Web UI Port, and port 6033 mapping.
- `CREDITS.md` attributing every bundled runtime tool (ghorg, gh, rclone, tini, jq, git, Debian) and every dev/CI tool (bats-core, ShellCheck, hadolint, gitleaks)
- README "Credits" section linking to `CREDITS.md`
- Dockerfile labels `org.opencontainers.image.documentation`, `org.opencontainers.image.vendor`, and `org.gitpreserver.dependencies`

### Changed
- `docker-compose.yml` `sync` and `daemon` services now fall back to mounting `/dev/null` when `GITPRESERVER_RCLONE_CONFIG` is not set, allowing env-var-only rclone configuration without a config file on disk
- `docker/entrypoint.sh` now reads `GITPRESERVER_MODE` and forks to `daemon-start.sh` when set to `daemon`, otherwise passes through to the original `"$@"` path

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
- `run-backup.sh` now accepts a positional destination path, `--no-sync`, and `--dry-run` flags
- Documentation now leads with GitHub fine-grained PATs (`github_pat_…`) and the per-repository least-privilege permissions model
- `GITPRESERVER_HOST_BACKUP_DIR` separates the host bind-mount path from the in-container `GITPRESERVER_BACKUP_DIR`

### Changed
- Container now runs as the non-root `gitpreserver` user (UID/GID 1000, overridable via `PUID`/`PGID`)
- `cap_drop: ALL` and `no-new-privileges:true` applied to all compose services
- `rclone.conf` is now mounted at `/home/gitpreserver/.config/rclone/rclone.conf`
- Tokens are passed to `ghorg`/`gh` exclusively via env vars; the previous `--token=` CLI flag exposed credentials in `ps`/`/proc`
- All log timestamps are now UTC (`YYYY-MM-DDTHH:MM:SSZ`)
- `run-backup.sh` now self-execs under `flock -n` to prevent overlapping cron runs

### Fixed
- `backup/mirror.sh` now uses ghorg's `--path` (absolute parent) flag with `--output-dir=repos`
- `backup/metadata.sh` now exports via `gh api --paginate | jq -s 'add // []'`; false-positive warnings on empty result sets eliminated
- `run-backup.sh` now honors `GITPRESERVER_DRY_RUN=true` set in the shell environment
- ghorg release asset URL — release files use `Linux` (capital L) and the `arm64` arch suffix
- `backup/metadata.sh` reported "1 repository" when the user had zero
- `backup/sync.sh` retention pruning switched to `find -print0` / `read -d ''`

### Security
- Input validation on `GITPRESERVER_USERNAME` and discovered repo names (`^[A-Za-z0-9._-]+$`)
- Numeric validation on `GITPRESERVER_RETENTION_DAYS` and `GITPRESERVER_RCLONE_TRANSFERS`
- `.dockerignore` prevents `.env`, `rclone.conf`, `.git/`, docs, and CI configs from entering the image build context

First public release. GitHub account backup (Phase 1).

[Unreleased]: https://github.com/RealDougEubanks/gitpreserver/compare/v2.1.0...HEAD
[2.1.0]: https://github.com/RealDougEubanks/gitpreserver/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/RealDougEubanks/gitpreserver/compare/v1.1.0...v2.0.0
[1.1.0]: https://github.com/RealDougEubanks/gitpreserver/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/RealDougEubanks/gitpreserver/releases/tag/v1.0.0
