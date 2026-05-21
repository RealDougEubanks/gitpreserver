# Setup — Linux and macOS

This guide covers first-time setup on any Linux or macOS host running Docker.

---

## Prerequisites

- Docker 24+ and Docker Compose v2
- A GitHub account with at least one repository
- A GitHub Personal Access Token (instructions below)
- An rclone-supported storage destination — or skip remote sync and keep backups local

On Linux, `flock` (from `util-linux`) is used by `run-backup.sh` to prevent overlapping cron runs. It's preinstalled on essentially every Linux distribution. macOS doesn't ship `flock`; the wrapper falls back to running without overlap protection (fine for interactive runs and ad-hoc testing). Install it with `brew install flock` if you cron-schedule GitPreserver on a Mac.

For Synology DSM, see [synology-setup.md](synology-setup.md).
For unRAID, see [unraid-setup.md](unraid-setup.md).

---

## Step 1 — Clone the repo

```bash
git clone https://github.com/dougeubanks/gitpreserver.git /opt/gitpreserver
cd /opt/gitpreserver
```

You can install it anywhere. `/opt/gitpreserver` is the recommended production path.

---

## Step 2 — Create a Personal Access Token

**GitHub:**
1. Go to **Settings → Developer settings → Personal access tokens → Tokens (classic)**
2. Click **Generate new token (classic)**
3. Give it a descriptive name (e.g. `gitpreserver`)
4. Set expiry — 1 year is a reasonable balance between security and convenience
5. Select scopes: `repo` (full), `read:user`
6. If you want to back up organization repositories: also select `read:org`
7. Click **Generate token** and copy it immediately — you can't see it again

---

## Step 3 — Configure

```bash
cp config/.env.example .env
```

Edit `.env`. At minimum, set:

```bash
GITPRESERVER_TOKEN=ghp_your_token_here
GITPRESERVER_USERNAME=your_github_username
```

To back up to a remote destination, also set `GITPRESERVER_RCLONE_REMOTE` to the name of a remote configured in `rclone/rclone.conf`. See [storage-backends.md](storage-backends.md) for annotated setup guides.

`.env` is in `.gitignore`. Never commit it.

---

## Step 4 — Configure rclone (if using remote sync)

```bash
cp rclone/rclone.conf.example rclone/rclone.conf
```

Edit `rclone/rclone.conf` and fill in credentials for your chosen backend. The example file has annotated templates for B2, S3, Google Drive, OneDrive, MEGA, SMB, and SFTP.

`rclone.conf` is in `.gitignore`. Never commit it.

---

## Step 5 — Build the Docker image

```bash
docker compose build
```

This builds a single image containing ghorg, gh CLI, and rclone. It takes a minute or two on first run; subsequent runs use the Docker layer cache.

### Host volume ownership

The container runs as a non-root user with **UID 1000 / GID 1000** by default. The `./backups` directory and `./rclone/rclone.conf` must be readable and writable by that UID, or the container will fail with `Permission denied`.

If your host user is already UID 1000 (the default on most Debian/Ubuntu installs), you're done — `./backups` will be created automatically with the right ownership.

If your host user is a different UID, you have two options:

1. **Recommended — override at runtime.** Set `PUID` and `PGID` in your shell or `.env` so the container runs as your host user:

   ```bash
   echo "PUID=$(id -u)" >> .env
   echo "PGID=$(id -g)" >> .env
   ```

2. **Alternative — chown the backup directory:**

   ```bash
   mkdir -p backups
   sudo chown -R 1000:1000 backups rclone/rclone.conf
   ```

On Synology and unRAID the platform packages handle this automatically — see the platform-specific setup guides.

---

## Step 6 — Run your first backup

```bash
./run-backup.sh
```

This runs all three stages in sequence:

1. **Mirror** — clones all repos into `./backups/YYYY-MM-DD/repos/`
2. **Metadata** — exports issues, PRs, and releases into `./backups/YYYY-MM-DD/metadata/`
3. **Sync** — pushes everything to your configured rclone remote

The first run takes longest — subsequent runs are incremental (rclone only transfers changed files).

To test the configuration without writing anything:

```bash
./run-backup.sh --dry-run
```

### Local-only backups (no rclone)

If you'd rather skip the rclone setup entirely and write backups to a NAS share, external disk, or any other host path, pass the destination as the first argument and add `--no-sync`:

```bash
# One-off backup to an external disk
./run-backup.sh /Volumes/Backup/github --no-sync

# Backup to a mounted NAS share
./run-backup.sh /mnt/nas/github --no-sync
```

The destination directory is created if it doesn't exist. Retention pruning still runs (so `GITPRESERVER_RETENTION_DAYS` is honored), but no rclone remote is contacted and `rclone.conf` does not need to exist.

`run-backup.sh --help` lists every option.

---

## Step 7 — Schedule with cron

```bash
crontab -e
```

Add a line for your preferred schedule. Adjust the install path if you cloned somewhere other than `/opt/gitpreserver`.

```
# Full run using .env settings (rclone + local)
0 2 * * 0  cd /opt/gitpreserver && ./run-backup.sh >> /var/log/gitpreserver.log 2>&1

# Local-only backup to a NAS share, no rclone
0 2 * * 0  /opt/gitpreserver/run-backup.sh /mnt/nas/github --no-sync >> /var/log/gitpreserver.log 2>&1
```

See `cron/crontab.example` for more schedules and patterns.

---

## Log rotation

To prevent `/var/log/gitpreserver.log` from growing unbounded, create a logrotate config:

```bash
sudo tee /etc/logrotate.d/gitpreserver <<'EOF'
/var/log/gitpreserver.log {
    weekly
    rotate 12
    compress
    delaycompress
    missingok
    notifempty
}
EOF
```

---

## Verifying a backup

After the first run, your backup directory should look like:

```
backups/
└── 2026-05-21/
    ├── repos/
    │   ├── your-repo.git/
    │   └── another-repo.git/
    └── metadata/
        ├── your-repo/
        │   ├── issues.json
        │   ├── pull_requests.json
        │   └── releases.json
        └── another-repo/
            └── ...
```

Each `.git` directory is a bare mirror clone. You can verify it with:

```bash
git --git-dir=backups/2026-05-21/repos/your-repo.git log --oneline -5
```

---

## Next steps

- [configuration.md](configuration.md) — full variable reference
- [storage-backends.md](storage-backends.md) — set up B2, S3, MEGA, and other remotes
- [encryption.md](encryption.md) — encrypt backups at rest
- [restoring.md](restoring.md) — restore a repo from a mirror backup
