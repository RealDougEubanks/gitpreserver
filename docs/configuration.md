# Configuration reference

GitPreserver follows the 12-Factor App convention: environment variables are the primary configuration method. A config file is supported as a convenience fallback.

---

## Precedence order

When a variable is defined in multiple places, the highest-priority source wins:

```
1. Environment variables    (GITPRESERVER_*)
2. Config file              (gitpreserver.conf)
3. Built-in defaults        (defined in the scripts)
```

---

## Environment variables

All variables are prefixed `GITPRESERVER_` to avoid collisions with other tools.

### Git host

| Variable | Default | Required | Description |
|---|---|---|---|
| `GITPRESERVER_TOKEN` | — | Yes | Personal Access Token for the git host |
| `GITPRESERVER_USERNAME` | — | Yes | Username or organization name to back up |
| `GITPRESERVER_HOST_TYPE` | `github` | No | `github` \| `bitbucket` \| `gitlab` \| `gitea` |
| `GITPRESERVER_HOST_URL` | — | For `gitea` | Custom host URL for self-hosted instances (e.g. `https://git.example.com`) |

**Token scopes by host:**

| Host | Required scopes |
|---|---|
| GitHub | `repo` (full), `read:user`. Add `read:org` for org repos. |
| Bitbucket | App Password with `Repositories: Read` |
| GitLab | Personal Access Token with `read_repository` |
| Gitea | Access Token (any scope that allows repo read) |

### Local storage

| Variable | Default | Description |
|---|---|---|
| `GITPRESERVER_BACKUP_DIR` | `/backups` | Path inside the container where backups are staged. Mount a host volume here. |
| `GITPRESERVER_RETENTION_DAYS` | `30` | Delete local snapshots older than this many days. Set to `0` to keep forever. |

### Remote sync (rclone)

| Variable | Default | Description |
|---|---|---|
| `GITPRESERVER_RCLONE_REMOTE` | — | rclone remote name. Must exist in `rclone.conf`. Leave blank to skip remote sync. |
| `GITPRESERVER_RCLONE_PATH` | `gitpreserver-backups` | Path or bucket on the remote. |
| `GITPRESERVER_RCLONE_CONFIG` | `./rclone/rclone.conf` | Host path to `rclone.conf`. Mounted read-only by `docker-compose.yml`. |
| `GITPRESERVER_RCLONE_TRANSFERS` | `4` | Number of parallel file transfers. |

### Encryption (rclone crypt)

| Variable | Default | Description |
|---|---|---|
| `GITPRESERVER_ENCRYPT` | `false` | Set to `true` to encrypt via rclone crypt. |
| `GITPRESERVER_CRYPT_REMOTE` | — | rclone crypt remote name. Required when `ENCRYPT=true`. |
| `GITPRESERVER_CRYPT_PASS` | — | Encryption passphrase. Generate: `openssl rand -base64 32`. |
| `GITPRESERVER_CRYPT_PASS2` | — | Salt. Generate: `rclone obscure your-salt-string`. |
| `GITPRESERVER_CRYPT_KEYFILE` | — | Path to a keyfile inside the container. |

See [encryption.md](encryption.md) for full setup instructions.

### Schedule

| Variable | Default | Description |
|---|---|---|
| `GITPRESERVER_SCHEDULE` | `0 2 * * 0` | Cron expression used by Synology and unRAID integrations. |

### Advanced

| Variable | Default | Description |
|---|---|---|
| `GITPRESERVER_CONFIG` | — | Explicit path to a `gitpreserver.conf` file. |
| `GITPRESERVER_LOG_LEVEL` | `info` | `debug` \| `info` \| `warn` \| `error` |
| `GITPRESERVER_DRY_RUN` | `false` | Set to `true` to run without writing or syncing anything. |

### Notifications (roadmap)

| Variable | Default | Description |
|---|---|---|
| `GITPRESERVER_WEBHOOK_URL` | — | Webhook URL for completion/failure notifications (not yet implemented). |

---

## Config file (optional)

The config file uses the same keys as env vars but in lowercase and without the `GITPRESERVER_` prefix. Environment variables always take precedence.

```ini
[gitpreserver]
token           = ghp_your_token_here
username        = your_github_username
host_type       = github
backup_dir      = /backups
retention_days  = 30
rclone_remote   = b2-remote
rclone_path     = gitpreserver-backups
encrypt         = false
log_level       = info
```

### Config file search order

If `GITPRESERVER_CONFIG` is not set, GitPreserver searches these paths and uses the first one found:

```
1. $GITPRESERVER_CONFIG
2. ./gitpreserver.conf            (current directory)
3. ~/.config/gitpreserver/gitpreserver.conf
4. /etc/gitpreserver/gitpreserver.conf
```

A missing config file is not an error.

---

## Security recommendations

- Never commit `.env` or `rclone.conf` to version control. Both are in `.gitignore`.
- Use `env_file: .env` in `docker-compose.yml`. Never put secrets in the compose file directly.
- Use a dedicated token with the minimum required scopes. Do not use a personal admin token.
- Mount `rclone.conf` read-only (`:ro`) to prevent accidental writes from inside the container.
- Store your encryption passphrase in Bitwarden immediately after generating it.
- On Synology and unRAID, set env vars through the platform UI rather than writing `.env` files to shared volumes.
