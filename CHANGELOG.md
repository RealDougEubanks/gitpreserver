# Changelog

All notable changes to GitPreserver are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
This project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

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

### Changed
- Container now runs as the non-root `gitpreserver` user (UID/GID 1000, overridable via `PUID`/`PGID`)
- `cap_drop: ALL` and `no-new-privileges:true` applied to all compose services
- `rclone.conf` is now mounted at `/home/gitpreserver/.config/rclone/rclone.conf` (set via `RCLONE_CONFIG`); previously `/root/.config/rclone/rclone.conf`
- Tokens are passed to `ghorg`/`gh` exclusively via env vars (`GHORG_*_TOKEN`, `GH_TOKEN`); the previous `--token=` CLI flag exposed credentials in `ps`/`/proc`
- All log timestamps are now UTC (`YYYY-MM-DDTHH:MM:SSZ`)
- `run-backup.sh` now self-execs under `flock -n` to prevent overlapping cron runs

### Fixed
- ghorg release asset URL — release files use `Linux` (capital L) and the `arm64` arch suffix; the previous URL would 404 on both amd64 and arm64
- `backup/metadata.sh` reported "1 repository" when the user had zero (`echo` on an empty string still emits a newline); now uses `mapfile` and an array length
- `backup/sync.sh` retention pruning: removed dead `${DRY_RUN:+}` token and switched to `find -print0` / `read -d ''` so unusual directory names cannot break `rm`

### Security
- Input validation on `GITPRESERVER_USERNAME` and discovered repo names (`^[A-Za-z0-9._-]+$`)
- Numeric validation on `GITPRESERVER_RETENTION_DAYS` and `GITPRESERVER_RCLONE_TRANSFERS`
- `.dockerignore` prevents `.env`, `rclone.conf`, `.git/`, docs, and CI configs from entering the image build context

---

## [1.0.0] — TBD

First public release. GitHub account backup (Phase 1).

[Unreleased]: https://github.com/dougeubanks/gitpreserver/compare/HEAD...HEAD
