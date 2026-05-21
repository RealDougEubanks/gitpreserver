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

---

## [1.0.0] — TBD

First public release. GitHub account backup (Phase 1).

[Unreleased]: https://github.com/dougeubanks/gitpreserver/compare/HEAD...HEAD
