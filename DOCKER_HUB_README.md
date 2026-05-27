# GitPreserver

<img src="https://github.com/RealDougEubanks/gitpreserver/blob/main/assets/icon-128.png?raw=true" alt="GitPreserver" width="80">

> A life preserver for your git repositories.
> Mirror your code, preserve your history, survive the flood.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://github.com/RealDougEubanks/gitpreserver/blob/main/LICENSE)
[![Docker Pulls](https://img.shields.io/docker/pulls/dougeubanks/gitpreserver)](https://hub.docker.com/r/dougeubanks/gitpreserver)
[![GitHub release](https://img.shields.io/github/v/release/RealDougEubanks/gitpreserver)](https://github.com/RealDougEubanks/gitpreserver/releases)
[![shellcheck](https://github.com/RealDougEubanks/gitpreserver/actions/workflows/lint.yml/badge.svg)](https://github.com/RealDougEubanks/gitpreserver/actions/workflows/lint.yml)

---

GitPreserver mirror-clones every repository in your git account — all branches, all tags, full history — and syncs encrypted backups to any rclone-supported destination on a schedule you control. It runs on any Linux/Docker host, Synology NAS, or unRAID server, and requires no persistent service.

GitHub suffered over 257 incidents between May 2025 and April 2026. If you've invested weeks building CI/CD pipelines, unit tests, and deployment configs across dozens of repositories, you need a safety net that doesn't depend on any single platform staying available.

---

## What it does

- **Mirror-clones** all repos for a configured account (all branches, all tags, full ref history) using [ghorg](https://github.com/gabrie30/ghorg)
- **Exports metadata** — issues, pull requests, and releases — as JSON sidecar files alongside the clones
- **Syncs** everything to any [rclone-supported destination](https://rclone.org/): Backblaze B2, AWS S3, Cloudflare R2, Google Drive, OneDrive, MEGA, SMB, NFS, local filesystem, and 70+ others
- **Encrypts** backups at rest via [rclone crypt](https://rclone.org/crypt/) (AES-256-CTR, optional)
- **Runs on a schedule** via cron — no persistent daemon required
- **Supports GitHub** (Phase 1), with Bitbucket, GitLab, Gitea, and generic git hosts on the roadmap

## What it doesn't do

- Back up GitHub Actions secrets (not API-exportable — document them in a password manager)
- Run a local git server
- Replace your git host

---

## Quick start

### Prerequisites

- Docker and Docker Compose
- A GitHub Personal Access Token — fine-grained (recommended) with **Contents**, **Metadata**, **Issues**, and **Pull requests** set to **Read**, or classic with `repo` + `read:user` scopes
- An rclone-supported storage destination (or use local-only mode)

### 1. Clone the repo

```bash
git clone https://github.com/RealDougEubanks/gitpreserver.git
cd gitpreserver
```

### 2. Configure

```bash
cp config/.env.example .env
```

Edit `.env` and set at minimum:

```bash
GITPRESERVER_TOKEN=github_pat_your_token_here
GITPRESERVER_USERNAME=your_github_username
```

To sync offsite, set `GITPRESERVER_RCLONE_REMOTE` to a remote configured in `rclone/rclone.conf`.

The container runs as a non-root user (UID/GID 1000 by default). If your host user differs, set `PUID` and `PGID` in `.env`:

```bash
echo "PUID=$(id -u)" >> .env
echo "PGID=$(id -g)" >> .env
```

### 3. Run a backup

```bash
./run-backup.sh                                  # full run using .env
./run-backup.sh /mnt/backup/github --no-sync     # local-only, no rclone
./run-backup.sh --dry-run                        # validate config, write nothing
```

### 4. Schedule it

```bash
crontab -e
```

Add a line — by default, Sundays at 2 AM:

```
0 2 * * 0  cd /opt/gitpreserver && ./run-backup.sh >> /var/log/gitpreserver.log 2>&1
```

---

## Platform support

| Platform | Status |
|---|---|
| Linux / macOS (Docker) | Ready |
| Synology DSM 7+ | Scaffolded |
| unRAID | Scaffolded |

---

## Configuration

All settings use environment variables prefixed `GITPRESERVER_`. Copy `config/.env.example` to `.env` — the file is fully commented.

| Variable | Default | Description |
|---|---|---|
| `GITPRESERVER_TOKEN` | — | Personal Access Token (required) |
| `GITPRESERVER_USERNAME` | — | Username or org to back up (required) |
| `GITPRESERVER_HOST_TYPE` | `github` | `github` \| `bitbucket` \| `gitlab` \| `gitea` |
| `GITPRESERVER_BACKUP_DIR` | `/backups` | Local backup staging path |
| `GITPRESERVER_RETENTION_DAYS` | `30` | Days to keep local snapshots (0 = keep forever) |
| `GITPRESERVER_RCLONE_REMOTE` | — | rclone remote name (blank = local only) |
| `GITPRESERVER_ENCRYPT` | `false` | Enable rclone crypt encryption |
| `GITPRESERVER_SCHEDULE` | `0 2 * * 0` | Cron expression |
| `GITPRESERVER_DRY_RUN` | `false` | No writes, no sync |

Full reference: [docs/configuration.md](https://github.com/RealDougEubanks/gitpreserver/blob/main/docs/configuration.md)

---

## Storage backends

Any rclone remote works — configure it in `rclone/rclone.conf` and point `GITPRESERVER_RCLONE_REMOTE` at its name.

Recommended default: **Backblaze B2** (~$0.006/GB/month, no egress fees to rclone).

See [docs/storage-backends.md](https://github.com/RealDougEubanks/gitpreserver/blob/main/docs/storage-backends.md) for setup guides covering B2, S3, MEGA, Google Drive, SMB/NFS, and more.

---

## Encryption

Set `GITPRESERVER_ENCRYPT=true` and configure a crypt remote in `rclone.conf`. Backups are encrypted with AES-256-CTR via rclone crypt. Store your passphrase in a password manager — there is no key escrow.

See [docs/encryption.md](https://github.com/RealDougEubanks/gitpreserver/blob/main/docs/encryption.md).

---

## Restoring

Mirrors are standard bare git repos. To push one to a new remote:

```bash
cd backups/2026-05-21/repos/your-repo.git
git remote add new-origin https://gitlab.com/YOUR_USERNAME/your-repo.git
git push --mirror new-origin
```

Issues, PRs, and releases are JSON files in `backups/YYYY-MM-DD/metadata/`.

Full restore guide: [docs/restoring.md](https://github.com/RealDougEubanks/gitpreserver/blob/main/docs/restoring.md)

---

## Roadmap

| Phase | Scope | Status |
|---|---|---|
| 1 | GitHub (user + org accounts) | In progress |
| 2 | Bitbucket and GitLab | Planned |
| 3 | Gitea, Forgejo, generic git hosts | Planned |
| — | Synology SPK | Scaffolded |
| — | unRAID Community Applications | Scaffolded |
| — | Multiple simultaneous destinations | Planned |
| — | Webhook notifications | Planned |

---

## Credits

Bundles [ghorg](https://github.com/gabrie30/ghorg), [gh](https://github.com/cli/cli), [rclone](https://github.com/rclone/rclone), [tini](https://github.com/krallin/tini), [jq](https://github.com/jqlang/jq), and [git](https://git-scm.com/) on a Debian base image. See [CREDITS.md](https://github.com/RealDougEubanks/gitpreserver/blob/main/CREDITS.md) for full attribution.

---

## License

[MIT](https://github.com/RealDougEubanks/gitpreserver/blob/main/LICENSE)
