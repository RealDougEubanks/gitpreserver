# GitPreserver — Project Plan

> A self-hosted, Docker-based git account backup tool that mirror-clones your repos,
> exports metadata, and syncs encrypted backups to any rclone-supported destination.
> Packaged for general Docker/Linux use, Synology DSM, and unRAID Community Applications.

---

## Table of Contents

1. [Why This Exists](#why-this-exists)
2. [Project Name & Branding](#project-name--branding)
3. [Domain Strategy](#domain-strategy)
4. [What It Does (and Doesn't)](#what-it-does-and-doesnt)
5. [Technology Stack](#technology-stack)
6. [Repository Structure](#repository-structure)
7. [Configuration System](#configuration-system)
8. [Core Components](#core-components)
9. [Docker Compose Design](#docker-compose-design)
10. [Storage Backends](#storage-backends)
11. [Encryption](#encryption)
12. [Scheduling](#scheduling)
13. [Synology SPK Package Plan](#synology-spk-package-plan)
14. [unRAID Community Applications Plan](#unraid-community-applications-plan)
15. [Documentation Plan](#documentation-plan)
16. [Build Milestones](#build-milestones)
17. [Publishing Checklist](#publishing-checklist)
18. [What Is NOT Backed Up](#what-is-not-backed-up)
19. [Restoring from Backup](#restoring-from-backup)

---

## Why This Exists

GitHub has experienced a significant decline in reliability. Between May 2025 and April 2026,
over 257 incidents were tracked — 48 classified as major outages — with GitHub Actions alone
suffering 57 disruptions. Uptime dropped below 90% at one point in 2025. A supply chain
compromise via a poisoned VS Code extension resulted in internal repo exfiltration in May 2026.

If you've invested weeks building CI/CD pipelines, Actions workflows, unit tests, secrets, and
deployment configurations across dozens of repositories, you need a safety net that doesn't
depend on any single platform staying online or your account remaining intact.

**GitPreserver** is that safety net — a life preserver for your git repositories.

---

## Project Name & Branding

### Chosen Name: GitPreserver

**The Name in One Sentence:**
*GitPreserver is a life preserver for your git repositories — throw it out before your
platform pulls you under.*

### Why GitPreserver?

The name was chosen after an extensive search process (documented below) that ruled out
over a dozen candidates due to namespace conflicts, squatted domains, or poor fit.
GitPreserver emerged as the clear winner for the following reasons:

**It sounds like "life preserver"** — the nautical rescue device. This isn't accidental.
The project exists because git hosting platforms have become unreliable. The life preserver
metaphor captures exactly what this tool does: it keeps your work afloat when the platform
you depend on starts taking on water. The analogy writes the tagline, the README intro,
and the project story without any additional effort.

**It's completely unambiguous** — unlike abstract names (RepoArk, GitVault), GitPreserver
tells you exactly what it does in the name itself. A developer encountering it for the first
time on a forum post or search result understands the purpose immediately.

**It's platform-agnostic** — "Git" rather than "GitHub" means the project naturally
supports GitHub, Bitbucket, GitLab, Gitea, and any other git host without the name
becoming misleading. This directly informed the phased roadmap.

**It owns its namespace** — zero conflicts found on GitHub, Docker Hub, npm, PyPI, or
anywhere else. Web search returns no competing projects. The `.com` domain was available
and unregistered (WHOIS confirmed May 2026).

### Naming Conventions

Consistency across contexts builds project credibility. Always use the correct form:

| Context | Form | Example |
|---|---|---|
| GitHub repo slug | `gitpreserver` | `github.com/USERNAME/gitpreserver` |
| Docker Hub image | `gitpreserver` | `docker pull USERNAME/gitpreserver` |
| Display name (README, docs, listings) | `GitPreserver` | `# GitPreserver` |
| Synology package name | `GitPreserver` | Package Center display name |
| unRAID app listing | `GitPreserver` | Community Applications name field |
| Environment variable prefix | `GITPRESERVER_` | `GITPRESERVER_GITHUB_TOKEN` |
| Log output prefix | `[gitpreserver]` | `[gitpreserver] Mirror complete.` |
| Config file name | `gitpreserver.conf` | `/etc/gitpreserver/gitpreserver.conf` |
| Domain | `gitpreserver.com` | Primary domain |
| SPK package field | `gitpreserver` | `package="gitpreserver"` |
| unRAID XML `<Name>` | `GitPreserver` | `<Name>GitPreserver</Name>` |

### Quick Reference Card

```
repo slug:     gitpreserver
display name:  GitPreserver
env prefix:    GITPRESERVER_
docker image:  USERNAME/gitpreserver
domain:        gitpreserver.com
log prefix:    [gitpreserver]
config file:   gitpreserver.conf
```

### README Tagline

```
# GitPreserver
> A life preserver for your git repositories.
> Mirror your code, preserve your history, survive the flood.
```

### Names That Were Considered and Ruled Out

This history is preserved so future contributors don't re-open the same questions.

**Round 1 — Initial Candidates**

| Name | Reason Ruled Out |
|---|---|
| `github-mirror-backup` | Original working title — too long for Docker images and branding |
| `repoguard` | Three separate active projects on GitHub (DLR-SC, prezi, b4lch) |
| `gitkeeper` | Active project at `github.com/erikh/gitkeeper`; conflicts with `git-keeper` |
| `gitsafe` | Taken on PyPI (identical use case), npm, and GitHub |
| `hubvault` | Clean namespace but permanently implies GitHub-only |
| `repovault` | Clean namespace; good but less memorable |

**Round 2 — Domain Availability Check (WHOIS)**

| Name | Outcome |
|---|---|
| `repoark` | All major TLDs taken |
| `gitark` | All major TLDs taken |
| `repohaven` | All major TLDs taken |
| `gitvault` | All major TLDs taken |
| `reporescue` | All major TLDs taken |
| `mirrorvault` | All major TLDs taken |

**Round 3 — Final Selection**

| Name | Outcome |
|---|---|
| `gitpreserver` | ✅ Namespace fully clean; `gitpreserver.com` available (WHOIS confirmed May 2026) |

---

## Domain Strategy

### Confirmed Availability (WHOIS verified May 2026)

| Domain | Status | Action |
|---|---|---|
| `gitpreserver.com` | ✅ Available | **Register immediately via Cloudflare Registrar** |
| `gitpreserver.dev` | ❌ Taken (squatted) | N/A |
| `gitpreserver.io` | ❌ Taken (squatted) | N/A |
| `gitpreserver.app` | ❌ Taken (squatted) | N/A |

Register `gitpreserver.com` before the repo goes public. Once indexed by search engines,
squatters will find it. At ~$10-12/year on Cloudflare Registrar this is cheap insurance.
Owning `.com` is the strongest possible outcome — no user will be confused or misdirected
by the unavailable TLDs.

### GitHub Pages (Free Documentation Site)

```
gitpreserver.com     CNAME     USERNAME.github.io/gitpreserver
```

Add a `CNAME` file to the repo root, enable GitHub Pages in repo settings, and add the
CNAME record in Cloudflare DNS.

---

## What It Does (and Doesn't)

### Does

- Mirror-clone **all repos** for a configured account (all branches, all tags, full ref history)
- Export **metadata** (issues, pull requests, releases) as structured JSON sidecars
- Sync backups to **any rclone-supported destination** (B2, S3, local, SMB, NFS, MEGA,
  Google Drive, OneDrive, and 70+ others)
- **Encrypt backups** at rest using rclone crypt (strong passphrase, keyfile, or both)
- Run **automatically on a schedule** via cron
- Work on **any Linux/Docker host**, Synology NAS (DSM 7+), and unRAID
- Support **GitHub** (Phase 1), **Bitbucket and GitLab** (Phase 2), and **generic git
  hosts** including Gitea, Forgejo, and self-hosted instances (Phase 3)

### Doesn't

- Back up GitHub Actions **secrets** (not exportable by design — document in a password manager)
- Replace your git host (no issue tracker UI, no PR workflow)
- Run a local Git server (use Gitea for that)
- Back up GitHub Pages or Gists (future roadmap)

---

## Technology Stack

| Layer | Tool | Why |
|---|---|---|
| Repo mirroring | `ghorg` (Phase 1) | Built for bulk user/org cloning with pagination and concurrency |
| Metadata export | `gh` CLI (Phase 1) | Official GitHub CLI; issues, PRs, releases as JSON |
| Offsite sync | `rclone` | Supports 70+ storage backends; built-in crypt for encryption |
| Encryption | `rclone crypt` | Transparent AES-256 encryption; passphrase or keyfile |
| Scheduling | Host `cron` | Simple, no extra container required |
| Orchestration | Docker Compose | Portable, repeatable, works on Linux/Synology/unRAID |
| Language | Bash | Minimal dependencies; readable; easy to audit |
| Config parsing | `dotenv` + shell | Env vars primary; config file fallback |

---

## Repository Structure

```
gitpreserver/
├── .github/
│   ├── workflows/
│   │   ├── lint.yml               # shellcheck on push
│   │   └── release.yml            # tag-triggered release build
│   └── ISSUE_TEMPLATE/
│       ├── bug_report.md
│       └── feature_request.md
│
├── backup/
│   ├── mirror.sh                  # Repo mirror clone runner
│   ├── metadata.sh                # Issues/PRs/releases JSON export
│   └── sync.sh                    # rclone sync to configured destination
│
├── docker/
│   └── Dockerfile                 # ghorg + gh CLI + rclone in one image
│
├── config/
│   ├── .env.example               # All variables with comments (canonical reference)
│   └── gitpreserver.conf.example  # Optional config file format (same keys, no prefix)
│
├── rclone/
│   └── rclone.conf.example        # Annotated rclone remote config templates
│
├── cron/
│   └── crontab.example            # Ready-to-use cron entry
│
├── synology/
│   ├── INFO                       # SPK package metadata
│   ├── PACKAGE_ICON.PNG           # 72x72 icon
│   ├── PACKAGE_ICON_256.PNG       # 256x256 icon
│   ├── scripts/
│   │   ├── start-stop-status      # DSM service lifecycle script
│   │   ├── preinst                # Pre-install checks
│   │   └── postinst               # Post-install setup
│   ├── conf/
│   │   └── resource               # DSM resource declarations
│   └── WIZARD_UIFILES/
│       └── install_uifile         # DSM install wizard UI (JSON)
│
├── unraid/
│   └── gitpreserver.xml           # Community Applications Docker template
│
├── docs/
│   ├── setup.md                   # Step-by-step first-time setup (generic)
│   ├── configuration.md           # Full configuration reference
│   ├── synology-setup.md          # Synology-specific install guide
│   ├── unraid-setup.md            # unRAID-specific install guide
│   ├── storage-backends.md        # rclone destination setup (B2, S3, MEGA, etc.)
│   ├── encryption.md              # rclone crypt setup and key management
│   ├── restoring.md               # How to restore from a mirror backup
│   └── what-is-not-backed-up.md   # Honest limitations doc
│
├── CNAME                          # gitpreserver.com   GitHub Pages
├── .gitignore                     # Ignores .env, backups/, rclone.conf
├── CHANGELOG.md
├── CONTRIBUTING.md
├── LICENSE                        # MIT
└── README.md
```

---

## Configuration System

### Design Philosophy

GitPreserver follows the **12-Factor App** methodology for configuration:

1. **Environment variables are the primary and preferred configuration method.**
   They work everywhere — bare metal, Docker, Kubernetes, CI/CD, Synology, unRAID —
   without modification. They are explicit, auditable, and never accidentally committed.

2. **A config file is supported as a convenience fallback**, not a replacement.
   It is useful for complex rclone setups or when managing multiple profiles, but
   env vars always take precedence when both are present.

3. **No configuration is embedded in code or Docker images.** All runtime behavior
   is externally configurable without rebuilding.

### Precedence Order (highest to lowest)

```
1. Environment variables          (GITPRESERVER_*)
2. Config file                    (gitpreserver.conf or path in GITPRESERVER_CONFIG)
3. Built-in defaults              (defined in scripts, documented in .env.example)
```

If a variable is set in both env and config file, the **environment variable wins**.
This follows standard Unix tooling conventions (see: git, rclone, aws-cli).

### Environment Variables

All variables are prefixed with `GITPRESERVER_` to avoid collisions with other tools
in the same environment. Variable names use `SCREAMING_SNAKE_CASE`.

```bash
# ============================================================
# GitPreserver Configuration
# Copy this file to .env and fill in your values.
# Environment variables always override config file values.
# Never commit .env to version control.
# ============================================================

# ------------------------------------------------------------
# Git Host (Phase 1: GitHub)
# ------------------------------------------------------------

# Personal Access Token
# GitHub: Settings   Developer settings   Personal access tokens
# Required scopes: repo (full), read:user
# For org repos add: read:org
GITPRESERVER_TOKEN=

# Username or organization name to back up
GITPRESERVER_USERNAME=

# Git host type: github | bitbucket | gitlab | gitea (default: github)
GITPRESERVER_HOST_TYPE=github

# Custom host URL — required for self-hosted GitLab, Gitea, etc.
# Leave blank for github.com, bitbucket.org, gitlab.com
GITPRESERVER_HOST_URL=

# ------------------------------------------------------------
# Backup Storage
# ------------------------------------------------------------

# Local path inside the container where backups are staged
# Mount a host volume here in docker-compose.yml
GITPRESERVER_BACKUP_DIR=/backups

# Number of days to retain local backup snapshots before pruning
# Set to 0 to disable pruning (keep forever)
GITPRESERVER_RETENTION_DAYS=30

# ------------------------------------------------------------
# Remote Sync (rclone)
# ------------------------------------------------------------

# Name of the rclone remote to sync to (must exist in rclone.conf)
# Examples: b2-remote, s3-remote, gdrive, onedrive, mega, local, smb-nas
# Leave blank to skip remote sync (local backup only)
GITPRESERVER_RCLONE_REMOTE=

# Path/bucket on the remote to sync into
GITPRESERVER_RCLONE_PATH=gitpreserver-backups

# Full path to rclone config file (default: /root/.config/rclone/rclone.conf)
GITPRESERVER_RCLONE_CONFIG=

# Number of parallel transfers (default: 4)
GITPRESERVER_RCLONE_TRANSFERS=4

# ------------------------------------------------------------
# Encryption (rclone crypt)
# ------------------------------------------------------------

# Set to true to enable rclone crypt encryption on the remote
# Requires GITPRESERVER_CRYPT_REMOTE to be configured in rclone.conf
GITPRESERVER_ENCRYPT=false

# Name of the rclone crypt remote (wraps GITPRESERVER_RCLONE_REMOTE)
# Must be configured in rclone.conf as a crypt remote
GITPRESERVER_CRYPT_REMOTE=

# Encryption passphrase (used if no keyfile is specified)
# Generate a strong passphrase: openssl rand -base64 32
# Store this in Bitwarden — without it your backup is unrecoverable
GITPRESERVER_CRYPT_PASS=

# Salt for password obfuscation (rclone obscure your-pass)
# Generate: rclone obscure your-passphrase
GITPRESERVER_CRYPT_PASS2=

# Path to a keyfile for encryption (alternative or supplement to passphrase)
# The keyfile must be mounted into the container if used
GITPRESERVER_CRYPT_KEYFILE=

# ------------------------------------------------------------
# Schedule (used by Synology/unRAID integrations)
# ------------------------------------------------------------

# Cron expression for scheduled runs (default: Sundays at 2 AM)
GITPRESERVER_SCHEDULE=0 2 * * 0

# ------------------------------------------------------------
# Notifications (future roadmap)
# ------------------------------------------------------------

# Webhook URL for backup completion/failure notifications
# Supports Slack, Discord, ntfy, and generic webhooks
GITPRESERVER_WEBHOOK_URL=

# ------------------------------------------------------------
# Advanced
# ------------------------------------------------------------

# Path to an optional config file (overrides built-in defaults only;
# env vars always take precedence over config file values)
GITPRESERVER_CONFIG=

# Log level: debug | info | warn | error (default: info)
GITPRESERVER_LOG_LEVEL=info

# Set to true to perform a dry run (no writes, no sync)
GITPRESERVER_DRY_RUN=false
```

### Config File (Optional)

The config file uses the same key names as env vars but **without the `GITPRESERVER_`
prefix** and in lowercase. This follows the convention used by tools like rclone, git,
and aws-cli where the config file is a human-friendly companion to env vars.

```ini
# /etc/gitpreserver/gitpreserver.conf
# or ~/.config/gitpreserver/gitpreserver.conf
# or any path set in GITPRESERVER_CONFIG
#
# Keys are lowercase, no prefix.
# Environment variables always take precedence over values here.

[gitpreserver]
token         = 
username      = 
host_type     = github
backup_dir    = /backups
retention_days = 30
rclone_remote = b2-remote
rclone_path   = gitpreserver-backups
encrypt       = false
log_level     = info
```

### Config File Search Order

If `GITPRESERVER_CONFIG` is not explicitly set, GitPreserver looks for a config file in
this order and uses the first one found:

```
1. $GITPRESERVER_CONFIG          (explicit override)
2. ./gitpreserver.conf           (current directory — useful for development)
3. ~/.config/gitpreserver/gitpreserver.conf   (user config)
4. /etc/gitpreserver/gitpreserver.conf        (system config)
```

If no config file is found, only environment variables and built-in defaults apply.
**A missing config file is not an error.**

### Security Best Practices for Configuration

- **Never commit `.env` to version control.** `.gitignore` includes it by default.
- **Never put secrets in `docker-compose.yml`** — use `env_file: .env` instead.
- **Store your encryption passphrase in Bitwarden** — if lost, backups are unrecoverable.
- **Use a dedicated token with minimum required scopes** — not a personal admin token.
- **Rotate tokens periodically** and update `.env` accordingly.
- **On Synology/unRAID**, set env vars through the platform UI rather than writing `.env`
  files to shared volumes where other users may have read access.
- **Mount rclone.conf read-only** (`:ro`) in Docker to prevent accidental modification.

---

## Core Components

### `backup/mirror.sh`

Mirror-clones all repos for the configured account into a dated snapshot directory.

```bash
#!/usr/bin/env bash
set -euo pipefail

BACKUP_DATE=$(date +%Y-%m-%d)
OUTPUT_DIR="${GITPRESERVER_BACKUP_DIR}/${BACKUP_DATE}/repos"

echo "[gitpreserver] Starting mirror clone for ${GITPRESERVER_USERNAME}   ${OUTPUT_DIR}"

ghorg clone "${GITPRESERVER_USERNAME}" \
  --clone-type=user \
  --backup \
  --token="${GITPRESERVER_TOKEN}" \
  --output-dir="${OUTPUT_DIR}" \
  --concurrency=4

echo "[gitpreserver] Mirror clone complete."
```

### `backup/metadata.sh`

Exports issues, PRs, and releases as JSON sidecar files alongside the mirror clones.
Phase 1 uses the `gh` CLI. Phase 2 will add Bitbucket and GitLab API equivalents.

### `backup/sync.sh`

Runs rclone sync to push the local backup snapshot to the configured remote.
If `GITPRESERVER_ENCRYPT=true`, syncs via the configured crypt remote instead.

```bash
#!/usr/bin/env bash
set -euo pipefail

REMOTE="${GITPRESERVER_ENCRYPT:+${GITPRESERVER_CRYPT_REMOTE}}${GITPRESERVER_ENCRYPT:-${GITPRESERVER_RCLONE_REMOTE}}"
DEST="${REMOTE}:${GITPRESERVER_RCLONE_PATH}"

echo "[gitpreserver] Syncing to ${DEST}"

rclone sync "${GITPRESERVER_BACKUP_DIR}" "${DEST}" \
  --transfers="${GITPRESERVER_RCLONE_TRANSFERS:-4}" \
  --log-level="${GITPRESERVER_LOG_LEVEL:-INFO}"

echo "[gitpreserver] Sync complete."
```

---

## Docker Compose Design

```yaml
services:

  mirror:
    build: ./docker
    volumes:
      - ./backups:/backups
    env_file: .env
    command: mirror.sh

  metadata:
    build: ./docker
    volumes:
      - ./backups:/backups
    env_file: .env
    command: metadata.sh
    depends_on:
      mirror:
        condition: service_completed_successfully

  sync:
    build: ./docker
    volumes:
      - ./backups:/backups
      - ./rclone/rclone.conf:/root/.config/rclone/rclone.conf:ro
    env_file: .env
    command: sync.sh
    depends_on:
      metadata:
        condition: service_completed_successfully
```

A `run-backup.sh` wrapper script calls all three in sequence and is what cron invokes.

---

## Storage Backends

GitPreserver uses **rclone** for all remote sync operations, which means any of rclone's
70+ supported backends work out of the box. No code changes required — just configure the
appropriate remote in `rclone.conf` and set `GITPRESERVER_RCLONE_REMOTE` to its name.

### Supported Destinations (non-exhaustive)

| Category | Examples |
|---|---|
| Object storage | Backblaze B2, AWS S3, Cloudflare R2, Wasabi, MinIO |
| Cloud drives | Google Drive, Microsoft OneDrive, Dropbox, MEGA |
| Self-hosted / NAS | Local filesystem, SMB/CIFS shares, NFS mounts, SFTP, WebDAV |
| Other cloud | Azure Blob Storage, IBM Cloud, Oracle Object Storage |

### Recommended Default: Backblaze B2

B2 is the recommended default for most users:
- Cheapest object storage at scale (~$0.006/GB/month)
- Native rclone support with no egress fees to rclone
- Simple bucket + application key setup
- Detailed setup in `docs/storage-backends.md`

### Local-Only Mode

Set `GITPRESERVER_RCLONE_REMOTE=` (empty) to skip remote sync entirely and keep backups
only on the local volume. Useful for NAS users who manage their own offsite strategy.

### Multiple Destinations (Future Roadmap)

A future version will support comma-separated remotes in `GITPRESERVER_RCLONE_REMOTE`
to sync to multiple destinations in a single run (e.g., B2 + local NFS simultaneously).

---

## Encryption

GitPreserver uses **rclone crypt** for transparent AES-256-CTR encryption of backups
at rest on the remote. Local staged backups are not encrypted by default — encrypt your
local volume at the OS level if required.

### How rclone crypt Works

rclone crypt is a wrapper remote that transparently encrypts files before they are sent
to the underlying storage backend and decrypts them on retrieval. It requires no changes
to the sync logic — only the remote name changes.

```
Local backups   rclone crypt (encrypt)   underlying remote (B2, S3, MEGA, etc.)
```

File names and directory structure are also encrypted by default, providing metadata
privacy in addition to content privacy.

### Enabling Encryption

**Step 1:** Configure a crypt remote in `rclone.conf` wrapping your storage remote:

```ini
[b2-remote]
type = b2
account = YOUR_B2_ACCOUNT_ID
key = YOUR_B2_APPLICATION_KEY

[gitpreserver-crypt]
type = crypt
remote = b2-remote:gitpreserver-backups
filename_encryption = standard
directory_name_encryption = true
password = RCLONE_OBSCURED_PASSPHRASE
password2 = RCLONE_OBSCURED_SALT
```

**Step 2:** Set env vars:

```bash
GITPRESERVER_ENCRYPT=true
GITPRESERVER_RCLONE_REMOTE=b2-remote
GITPRESERVER_CRYPT_REMOTE=gitpreserver-crypt
GITPRESERVER_CRYPT_PASS=your-strong-passphrase
GITPRESERVER_CRYPT_PASS2=your-salt
```

### Key / Passphrase Options

| Method | How | When to Use |
|---|---|---|
| Passphrase | `GITPRESERVER_CRYPT_PASS` | Standard use — generate with `openssl rand -base64 32` |
| Passphrase + salt | `GITPRESERVER_CRYPT_PASS` + `GITPRESERVER_CRYPT_PASS2` | Recommended — salt hardens against brute force |
| Keyfile | `GITPRESERVER_CRYPT_KEYFILE` | High-security environments; mount keyfile into container |
| Passphrase + keyfile | Both set | Maximum security; both required for decryption |

### Critical: Passphrase Backup

**Store your encryption passphrase in Bitwarden immediately.** Without it, your encrypted
backup is permanently unrecoverable — rclone crypt uses no key escrow. Document both
`GITPRESERVER_CRYPT_PASS` and `GITPRESERVER_CRYPT_PASS2` as a secure note.

---

## Scheduling

### Linux / Mac (cron)

```bash
# Run every Sunday at 2:00 AM
0 2 * * 0 cd /opt/gitpreserver && ./run-backup.sh >> /var/log/gitpreserver.log 2>&1
```

Log rotation via `/etc/logrotate.d/gitpreserver` documented in `docs/setup.md`.

### Synology Task Scheduler

The SPK package registers a scheduled task automatically post-install using the
`GITPRESERVER_SCHEDULE` cron expression.

### unRAID

Use the **User Scripts** plugin with `GITPRESERVER_SCHEDULE` as the cron expression,
or trigger manually from the Community Applications UI.

---

## Synology SPK Package Plan

### `INFO` File (Key Fields)

```
package="gitpreserver"
version="1.0.0-1"
arch="noarch"
displayname="GitPreserver"
maintainer="Doug Eubanks"
maintainer_url="https://github.com/USERNAME/gitpreserver"
distributor="Doug Eubanks"
description="A life preserver for your git repositories. Mirror-clones all repos, exports metadata, and syncs encrypted backups to Backblaze B2, S3, MEGA, Google Drive, or any rclone destination."
os_min_ver="7.0-40000"
install_dep_packages="Docker"
support_url="https://github.com/USERNAME/gitpreserver/issues"
```

### Install Wizard Fields

- Git host type (GitHub / Bitbucket / GitLab / Gitea)
- Username or organization
- Personal Access Token
- Backup destination path (default: `/volume1/gitpreserver-backups`)
- Remote type (B2 / S3 / Google Drive / OneDrive / MEGA / SMB / Local / Other)
- Remote credentials (dynamic based on type selection)
- Enable encryption (yes/no)
- Encryption passphrase (if enabled)
- Schedule (daily / weekly / manual)

### DSM Integration Notes

- Wraps `docker compose run` — Docker must be installed from Package Center first
- `start-stop-status` manages the scheduled task, not a persistent daemon
- Target: **DSM 7.1+** on x86_64 and ARM64
- Build toolchain: **spksrc**
- Submission: **SynoCommunity** and/or **Community Package Hub**

---

## unRAID Community Applications Plan

### Template File: `unraid/gitpreserver.xml`

```xml
<?xml version="1.0"?>
<Container version="2">
  <Name>GitPreserver</Name>
  <Repository>USERNAME/gitpreserver</Repository>
  <Registry>https://hub.docker.com/r/USERNAME/gitpreserver</Registry>
  <Network>bridge</Network>
  <Privileged>false</Privileged>
  <Support>https://forums.unraid.net/topic/XXXXX-gitpreserver</Support>
  <Project>https://github.com/USERNAME/gitpreserver</Project>
  <Overview>
    A life preserver for your git repositories. Mirror-clones all your repos with full
    branch and tag history, exports issues/PRs/releases as JSON, and syncs encrypted
    backups to Backblaze B2, S3, Google Drive, OneDrive, MEGA, SMB, or any
    rclone-supported destination.
  </Overview>
  <Category>Backup: Tools:</Category>
  <Icon>https://raw.githubusercontent.com/USERNAME/gitpreserver/main/assets/icon.png</Icon>
  <Config Name="Token" Target="GITPRESERVER_TOKEN" Default="" Mode=""
    Description="Personal Access Token (repo scope)" Type="Variable" Display="always" Required="true"/>
  <Config Name="Username" Target="GITPRESERVER_USERNAME" Default="" Mode=""
    Description="GitHub/GitLab/Bitbucket username or org" Type="Variable" Display="always" Required="true"/>
  <Config Name="Host Type" Target="GITPRESERVER_HOST_TYPE" Default="github" Mode=""
    Description="github | bitbucket | gitlab | gitea" Type="Variable" Display="always" Required="true"/>
  <Config Name="Backup Path" Target="/backups" Default="/mnt/user/appdata/gitpreserver"
    Mode="rw" Description="Local backup storage path" Type="Path" Display="always" Required="true"/>
  <Config Name="rclone Remote" Target="GITPRESERVER_RCLONE_REMOTE" Default="" Mode=""
    Description="rclone remote name (leave blank for local only)" Type="Variable" Display="always" Required="false"/>
  <Config Name="rclone Path" Target="GITPRESERVER_RCLONE_PATH" Default="gitpreserver-backups" Mode=""
    Description="Path/bucket on the remote" Type="Variable" Display="always" Required="false"/>
  <Config Name="rclone Config" Target="/root/.config/rclone/rclone.conf" Default=""
    Mode="ro" Description="Path to rclone.conf on host" Type="Path" Display="always" Required="false"/>
  <Config Name="Enable Encryption" Target="GITPRESERVER_ENCRYPT" Default="false" Mode=""
    Description="true to encrypt backups via rclone crypt" Type="Variable" Display="advanced" Required="false"/>
  <Config Name="Crypt Remote" Target="GITPRESERVER_CRYPT_REMOTE" Default="" Mode=""
    Description="rclone crypt remote name (if encryption enabled)" Type="Variable" Display="advanced" Required="false"/>
  <Config Name="Retention Days" Target="GITPRESERVER_RETENTION_DAYS" Default="30" Mode=""
    Description="Days to keep local snapshots" Type="Variable" Display="advanced" Required="false"/>
  <Config Name="Schedule" Target="GITPRESERVER_SCHEDULE" Default="0 2 * * 0" Mode=""
    Description="Cron expression for backup schedule" Type="Variable" Display="advanced" Required="false"/>
  <Config Name="Log Level" Target="GITPRESERVER_LOG_LEVEL" Default="info" Mode=""
    Description="debug | info | warn | error" Type="Variable" Display="advanced" Required="false"/>
</Container>
```

---

## Documentation Plan

| File | Contents |
|---|---|
| `README.md` | Overview, quick start, prerequisites, feature list, badge row |
| `docs/configuration.md` | Full variable and config file reference |
| `docs/setup.md` | Generic Linux/Mac setup — clone, configure, run, schedule |
| `docs/synology-setup.md` | DSM Package Center install, Task Scheduler config |
| `docs/unraid-setup.md` | CA install, User Scripts scheduling, path conventions |
| `docs/storage-backends.md` | rclone setup for B2, S3, MEGA, Google Drive, SMB, NFS, etc. |
| `docs/encryption.md` | rclone crypt setup, key management, passphrase backup |
| `docs/restoring.md` | How to restore: `git push --mirror`, metadata JSON, decrypt |
| `docs/what-is-not-backed-up.md` | Secrets, runners, environment config — manual documentation |
| `CONTRIBUTING.md` | PR guidelines, local dev setup, testing |
| `CHANGELOG.md` | Semver changelog |

### README Badge Row

```markdown
![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)
![Docker Pulls](https://img.shields.io/docker/pulls/USERNAME/gitpreserver)
![GitHub release](https://img.shields.io/github/v/release/USERNAME/gitpreserver)
![shellcheck](https://github.com/USERNAME/gitpreserver/actions/workflows/lint.yml/badge.svg)
```

---

## Build Milestones

### Phase 1 — GitHub (MVP)

**Goal:** Full working backup tool for GitHub accounts.

- [ ] `git init gitpreserver` — public repo scaffold
- [ ] `README.md` stub, `LICENSE` (MIT), `.gitignore`, `CHANGELOG.md`, `CNAME`
- [ ] `.env.example` with all `GITPRESERVER_` variables, fully commented
- [ ] `config/gitpreserver.conf.example` with config file format
- [ ] `docker/Dockerfile` (ghorg + gh CLI + rclone)
- [ ] `backup/mirror.sh` — GitHub mirror clone via ghorg
- [ ] `backup/metadata.sh` — issues/PRs/releases via gh CLI
- [ ] `backup/sync.sh` — rclone sync with crypt support
- [ ] `docker-compose.yml` — all three services with `depends_on`
- [ ] `run-backup.sh` — single entrypoint wrapper
- [ ] `rclone/rclone.conf.example` — annotated templates for B2, S3, MEGA, Drive, SMB
- [ ] `cron/crontab.example`
- [ ] Local retention pruning (`GITPRESERVER_RETENTION_DAYS`)
- [ ] `docs/setup.md`, `docs/storage-backends.md`, `docs/encryption.md`
- [ ] GitHub Actions: `lint.yml` (shellcheck), `release.yml`
- [ ] Register `gitpreserver.com`, point at GitHub Pages
- [ ] Tag `v1.0.0`

### Phase 2 — Bitbucket and GitLab

**Goal:** Drop-in support for the two other major hosted platforms.

- [ ] Bitbucket mirror support via `ghorg` (already supported) + Bitbucket API metadata
- [ ] GitLab mirror support via `ghorg` + GitLab API metadata (issues, MRs, releases)
- [ ] `GITPRESERVER_HOST_TYPE=bitbucket|gitlab` routing in scripts
- [ ] Update `docs/configuration.md` with host-specific token scopes
- [ ] Tag `v2.0.0`

### Phase 3 — Generic Git Backends

**Goal:** Support any self-hosted or niche git platform.

- [ ] Gitea / Forgejo support via Gitea API
- [ ] Generic git host support via direct `git clone --mirror` (no API metadata)
- [ ] `GITPRESERVER_HOST_TYPE=gitea|generic` routing
- [ ] `GITPRESERVER_HOST_URL` for self-hosted instances
- [ ] Tag `v3.0.0`

### Ongoing — Polish and Platform Packaging

- [ ] Synology SPK (spksrc build + SynoCommunity submission)
- [ ] unRAID Community Applications template + Unraid forum thread
- [ ] Multiple destination support (`GITPRESERVER_RCLONE_REMOTE` as comma-separated list)
- [ ] Webhook notifications on completion/failure
- [ ] `docs/restoring.md` and `docs/what-is-not-backed-up.md`
- [ ] `CONTRIBUTING.md`

---

## Publishing Checklist

### GitHub

- [ ] Repo public at `github.com/USERNAME/gitpreserver` with MIT license
- [ ] README quick-start works end-to-end from a fresh clone
- [ ] `.env.example` complete and fully commented
- [ ] No secrets committed (verified via `git log` and `git secret` scan)
- [ ] GitHub Actions lint passing on `main`

### Docker Hub

- [ ] Image published as `USERNAME/gitpreserver`
- [ ] `latest`, `v1.0.0` tags present
- [ ] Docker Hub description matches README

### SynoCommunity / CPHub

- [ ] Account registered
- [ ] SPK passes server-side validation
- [ ] Team review complete

### unRAID Community Applications

- [ ] Docker Hub image public and accessible
- [ ] XML template validates
- [ ] Dedicated support thread on `forums.unraid.net`
- [ ] Repo URL submitted to CA maintainer

---

## What Is NOT Backed Up

| Item | Why | Mitigation |
|---|---|---|
| GitHub Actions Secrets | Not exportable via API | Document in Bitwarden |
| Actions Environment Config | Protection rules, reviewers | Screenshot or document manually |
| GitHub Apps / OAuth configs | Platform-specific | Note app names and scopes |
| Branch protection rules | API-readable but not in git | Export via `gh api` — roadmap item |
| GitHub Pages config | Tied to repo settings | Document custom domain / build settings |
| CI/CD runner config | Platform-specific | Document runner labels and environment |

---

## Restoring from Backup

Full instructions in `docs/restoring.md`. Short version:

### Decrypt (if encryption was enabled)

```bash
# Configure the crypt remote in rclone.conf with your passphrase
# then sync down before restoring
rclone sync gitpreserver-crypt:gitpreserver-backups /local/restore/path
```

### Push a Mirror to a New Remote

```bash
cd /backups/2026-05-21/repos/your-repo.git

git remote add new-origin https://gitlab.com/YOUR_USERNAME/your-repo.git
git push --mirror new-origin
```

### Restore Metadata

Issues and PRs are in JSON sidecar files. Re-import scripts for GitHub, GitLab, and
Bitbucket APIs are on the Phase 1/2 roadmap.

---

## License

MIT — free to use, modify, and distribute. Contributions welcome.

---

*Plan version: 1.3 — May 2026*
*Naming history: github-mirror-backup   RepoArk   GitPreserver*
*Author: Doug Eubanks — doug.eubanks@atlanticbt.com — 919-822-1881*
