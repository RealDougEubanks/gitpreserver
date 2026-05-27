<!--
doc: ENV_VARS
last-refreshed: 2026-05-27
generated-by: doc-refresh skill
-->

# Environment Variables

> **SECURITY:** Never log, share, or commit values from `.env`.
> If a secret is exposed, rotate it immediately — there is no automated detection.

Copy `config/.env.example` to `.env` and fill in all required values before running.

```bash
cp config/.env.example .env
```

---

## Git host (required)

| Variable | Required | Default | Description | Used in |
|----------|----------|---------|-------------|---------|
| `GITPRESERVER_TOKEN` | **Yes** | — | Personal Access Token for the git host. For GitHub, use a fine-grained PAT (`github_pat_…`) with Contents, Metadata, Issues, and Pull requests set to Read. | `backup/mirror.sh`, `backup/metadata.sh` |
| `GITPRESERVER_USERNAME` | **Yes** | — | Username or organization name to back up. | `backup/mirror.sh`, `backup/metadata.sh` |
| `GITPRESERVER_HOST_TYPE` | No | `github` | `github` \| `bitbucket` \| `gitlab` \| `gitea` | `backup/mirror.sh` |
| `GITPRESERVER_HOST_URL` | For self-hosted | — | Custom host URL for self-hosted GitLab, Gitea, Forgejo, etc. Leave blank for github.com / bitbucket.org / gitlab.com. Example: `https://git.example.com` | `backup/mirror.sh` |

> **SECURITY:** `GITPRESERVER_TOKEN` is passed to `ghorg` and `gh` via their documented environment variables only.
> It is never written to disk, passed as a CLI flag, or logged.

---

## Local storage

| Variable | Required | Default | Description | Used in |
|----------|----------|---------|-------------|---------|
| `GITPRESERVER_HOST_BACKUP_DIR` | No | `./backups` | **Host** path bind-mounted into the container at `/backups`. Use an absolute path in production (e.g. `/opt/gitpreserver/backups`). | `run-backup.sh`, `docker-compose.yml` |
| `GITPRESERVER_BACKUP_DIR` | No | `/backups` | **Container** path the scripts write to. Most users should not change this. | `backup/*.sh` |
| `GITPRESERVER_RETENTION_DAYS` | No | `30` | Delete local snapshots older than this many days. Set to `0` to keep forever. | `backup/sync.sh` |

---

## Remote sync (rclone)

| Variable | Required | Default | Description | Used in |
|----------|----------|---------|-------------|---------|
| `GITPRESERVER_RCLONE_REMOTE` | No | — | rclone remote name. Must exist in `rclone.conf` (or be defined via `RCLONE_CONFIG_*` env vars). Leave blank for local-only backups. | `backup/sync.sh` |
| `GITPRESERVER_RCLONE_PATH` | No | `gitpreserver-backups` | Bucket or path on the remote to sync into. | `backup/sync.sh` |
| `GITPRESERVER_RCLONE_CONFIG` | No | `./rclone/rclone.conf` | Host path to `rclone.conf`. Mounted read-only by `docker-compose.yml`. Leave blank to use `RCLONE_CONFIG_*` env vars instead. | `docker-compose.yml` |
| `GITPRESERVER_RCLONE_TRANSFERS` | No | `4` | Number of parallel file transfers. | `backup/sync.sh` |

See [`docs/storage-backends.md`](storage-backends.md) for per-backend setup guides.

---

## Encryption (rclone crypt)

> **SECURITY:** If `GITPRESERVER_CRYPT_PASS` is lost, the backup is permanently unrecoverable.
> Store it in Bitwarden before setting it here.

| Variable | Required | Default | Description | Used in |
|----------|----------|---------|-------------|---------|
| `GITPRESERVER_ENCRYPT` | No | `false` | Set to `true` to encrypt backups via rclone crypt (AES-256-CTR). | `backup/sync.sh` |
| `GITPRESERVER_CRYPT_REMOTE` | If ENCRYPT=true | — | rclone crypt remote name. Must be configured in `rclone.conf`. | `backup/sync.sh` |
| `GITPRESERVER_CRYPT_PASS` | No | — | Encryption passphrase. Usually read from `rclone.conf` in obscured form. If set here, use the **plaintext** value — rclone obscures it at runtime. Generate: `openssl rand -base64 32` | `backup/sync.sh` |
| `GITPRESERVER_CRYPT_PASS2` | No | — | Salt for passphrase hardening. Generate: `rclone obscure your-salt-string` | `backup/sync.sh` |
| `GITPRESERVER_CRYPT_KEYFILE` | No | — | Path to a keyfile **inside the container**. Mount it in with a volume if used. | `backup/sync.sh` |

See [`docs/encryption.md`](encryption.md) for full setup instructions.

---

## Run mode

| Variable | Required | Default | Description | Used in |
|----------|----------|---------|-------------|---------|
| `GITPRESERVER_MODE` | No | `oneshot` | `oneshot`: run backup once and exit. `daemon`: stay running, fire backups on schedule, serve web UI. | `docker/entrypoint.sh` |
| `GITPRESERVER_SCHEDULE` | No | `0 2 * * 0` | Five-field cron expression. Used by daemon mode internally and as a reference for external schedulers. Default: every Sunday at 02:00 UTC. | `docker/daemon-start.sh` |
| `GITPRESERVER_WEB_PORT` | No | `6033` | Web UI port (daemon mode only). | `docker/webserver.py`, `docker-compose.yml` |

---

## Container identity

| Variable | Required | Default | Description | Used in |
|----------|----------|---------|-------------|---------|
| `PUID` | No | `1000` | UID the container runs the workload as. Set to `$(id -u)` to match your host user. On unRAID, use `99` (nobody). | `docker/entrypoint.sh` |
| `PGID` | No | `1000` | GID the container runs the workload as. Set to `$(id -g)`. On unRAID, use `100` (users). | `docker/entrypoint.sh` |
| `UMASK` | No | — | Octal umask for files written by the container (e.g. `022`). | `docker/entrypoint.sh` |

---

## Advanced

| Variable | Required | Default | Description | Used in |
|----------|----------|---------|-------------|---------|
| `GITPRESERVER_CONFIG` | No | — | Path to an optional `gitpreserver.conf` file. Env vars always take precedence. | `backup/run-stages.sh` |
| `GITPRESERVER_LOG_LEVEL` | No | `info` | `debug` \| `info` \| `warn` \| `error` | `backup/*.sh` |
| `GITPRESERVER_DRY_RUN` | No | `false` | Set to `true` to run without writing repos, syncing, or deleting anything. | `backup/*.sh`, `run-backup.sh` |
| `GITPRESERVER_LOCK_FILE` | No | `.gitpreserver.lock` | Path to the flock lock file used to prevent concurrent runs. | `run-backup.sh` |

---

## rclone via environment variables (no rclone.conf required)

rclone reads remote config from env vars using the pattern `RCLONE_CONFIG_<REMOTE>_<KEY>=value`. Remote names are uppercased; hyphens become underscores.

Example — Backblaze B2 with encryption:

```bash
RCLONE_CONFIG_B2_TYPE=b2
RCLONE_CONFIG_B2_ACCOUNT=your_account_id
RCLONE_CONFIG_B2_KEY=your_app_key

RCLONE_CONFIG_MYCRYPT_TYPE=crypt
RCLONE_CONFIG_MYCRYPT_REMOTE=b2:gitpreserver-backups
RCLONE_CONFIG_MYCRYPT_FILENAME_ENCRYPTION=standard
RCLONE_CONFIG_MYCRYPT_DIRECTORY_NAME_ENCRYPTION=true
RCLONE_CONFIG_MYCRYPT_PASSWORD=<output of: rclone obscure 'your-passphrase'>
RCLONE_CONFIG_MYCRYPT_PASSWORD2=<output of: rclone obscure 'your-salt'>

GITPRESERVER_RCLONE_REMOTE=b2
GITPRESERVER_ENCRYPT=true
GITPRESERVER_CRYPT_REMOTE=mycrypt
```

Leave `GITPRESERVER_RCLONE_CONFIG` blank when using this approach.

---

## Notifications (roadmap — not yet implemented)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `GITPRESERVER_WEBHOOK_URL` | No | — | Webhook URL for backup completion and failure notifications. Supports Slack, Discord, ntfy, and generic webhooks. |

---

## Getting secret values

| Secret | How to obtain |
|--------|--------------|
| GitHub PAT | GitHub → Settings → Developer settings → Personal access tokens |
| Backblaze B2 key | Backblaze dashboard → App Keys → Add a New Application Key |
| AWS S3 key | AWS IAM → Users → Security credentials |
| Cloudflare R2 key | Cloudflare dashboard → R2 → Manage R2 API tokens |
| rclone obscured password | `docker run --rm dougeubanks/gitpreserver rclone obscure 'your-plaintext-password'` |
