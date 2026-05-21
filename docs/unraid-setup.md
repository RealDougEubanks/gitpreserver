# Setup — unRAID

This guide covers installing GitPreserver on an unRAID server. Two paths are documented: the Community Applications (CA) template for the typical case, and a CLI install for users who want to run on the host alongside other tooling.

---

## Prerequisites

- unRAID 6.10+ with Docker enabled
- The **Community Applications** plugin installed
- A GitHub Personal Access Token — fine-grained (`github_pat_…`) is recommended; see the project [README](../README.md) for the exact least-privilege permissions
- Optional: an rclone-supported destination (Backblaze B2, S3, Google Drive, etc.) if you want offsite sync

---

## Option A — Community Applications template

### Install

1. Open **Apps** in the unRAID UI.
2. Search for **GitPreserver**. (Until the template is approved by the CA maintainers, add this repo's template URL manually under **Apps → Settings → Template Repositories**: `https://github.com/RealDougEubanks/gitpreserver`.)
3. Click **Install**. The template opens with sensible defaults.

### Required fields

| Field | What to enter |
|---|---|
| **Personal Access Token** | Your `github_pat_…` or `ghp_…` token |
| **Username or Org** | The GitHub account whose repos you want backed up |
| **Backup Path** | Host directory for backup snapshots — default `/mnt/user/appdata/gitpreserver/backups` |

### Optional fields

| Field | What to enter |
|---|---|
| **rclone Remote** | Name of an rclone remote configured in your `rclone.conf`. Leave blank for local-only backup. |
| **rclone Bucket / Path** | Path or bucket on the remote (default: `gitpreserver-backups`) |
| **rclone Config File** | Host path to your `rclone.conf`. Required only when an rclone remote is set above. |
| **Enable Encryption** + **Crypt Remote** | For rclone crypt encryption at rest |
| **Retention Days** | How many days of dated snapshots to keep (default 30) |
| **PUID / PGID / UMASK** | UID/GID the backup files are written as. Defaults to unRAID's `nobody:users` (99:100). |

### First run

Click **Apply** to save. unRAID pulls the image and starts the container, which runs **once**, performs the backup, and exits. The container status will move from "started" to "exited"; that's expected — GitPreserver is a one-shot batch job, not a long-running service.

Verify the backup landed on disk:

```bash
ls /mnt/user/appdata/gitpreserver/backups/$(date -u +%Y-%m-%d)/repos/
```

You should see one bare clone (`*.git`) per repository.

### Schedule recurring backups with User Scripts

unRAID's CA UI doesn't schedule containers directly. Use the **User Scripts** plugin:

1. Install **User Scripts** from Community Applications.
2. Open **Settings → User Scripts → Add New Script**, name it `gitpreserver-nightly`.
3. Click the gear icon → **Edit Script** and paste:
   ```bash
   #!/bin/bash
   docker start -a GitPreserver
   ```
4. Set the schedule. Examples:
   - Daily at 2 AM: `0 2 * * *`
   - Weekly Sunday at 2 AM: `0 2 * * 0`
5. Save and enable the schedule.

The `-a` flag attaches stdout/stderr so User Scripts captures the backup log in its run history.

### First-run validation

Set **Dry Run** to `true` in the template, click **Apply**, and check the container log:

```
[gitpreserver] ... DRY RUN: would mirror your_user (github) -> /backups/.../repos
[gitpreserver] ... DRY RUN: would export metadata for your_user (github) -> /backups/.../metadata
[gitpreserver] ... GITPRESERVER_RCLONE_REMOTE is not set -- skipping remote sync ...
```

If you see those lines and no errors, your token and paths are valid. Set Dry Run back to `false` and click Apply for the real run.

---

## Option B — Manual install on the unRAID host

Use this if you'd rather pull the repo onto the host and use `docker compose` directly (e.g. you want to use the `./run-backup.sh /path --no-sync` local-only mode without the CA template).

### 1. SSH or open the unRAID terminal

```bash
ssh root@your-unraid-ip
```

### 2. Clone the repo to appdata

```bash
mkdir -p /mnt/user/appdata/gitpreserver
cd /mnt/user/appdata/gitpreserver
git clone https://github.com/RealDougEubanks/gitpreserver.git .
```

### 3. Configure

```bash
cp config/.env.example .env
vi .env
```

Set at minimum:

```bash
GITPRESERVER_TOKEN=github_pat_your_token_here
GITPRESERVER_USERNAME=your_github_username
GITPRESERVER_HOST_BACKUP_DIR=/mnt/user/appdata/gitpreserver/backups
PUID=99
PGID=100
```

If you want offsite sync, also drop your `rclone.conf` into `/mnt/user/appdata/gitpreserver/rclone/rclone.conf` and set `GITPRESERVER_RCLONE_REMOTE`. See [storage-backends.md](storage-backends.md).

### 4. Test

```bash
./run-backup.sh --dry-run
./run-backup.sh                  # real run; ~5 minutes for a typical account
```

### 5. Schedule with User Scripts

Same as Option A's User Scripts step, but the script body becomes:

```bash
#!/bin/bash
cd /mnt/user/appdata/gitpreserver && ./run-backup.sh
```

For a local-only nightly backup to a different array path, replace with:

```bash
#!/bin/bash
cd /mnt/user/appdata/gitpreserver && ./run-backup.sh /mnt/user/backups/github --no-sync
```

---

## Paths reference

| What | Path |
|---|---|
| Project files (Option B only) | `/mnt/user/appdata/gitpreserver/` |
| Backup snapshots | `/mnt/user/appdata/gitpreserver/backups/YYYY-MM-DD/` |
| `.env` (Option B only) | `/mnt/user/appdata/gitpreserver/.env` |
| `rclone.conf` | `/mnt/user/appdata/gitpreserver/rclone.conf` (Option A) or `.../rclone/rclone.conf` (Option B) |

---

## Notes

- unRAID's default `nobody:users` UID/GID is `99:100`. The template's PUID/PGID defaults match this so backup files appear with the expected ownership in your shares.
- Point your backup path at the array (`/mnt/user/...`) rather than the cache pool or RAM disk if you want backups to survive a reboot of the cache pool.
- If you use Mover to tier data between cache and array, your backup share will be tiered like any other. This is expected.
- The container is a **one-shot batch job**. A "Stopped" status in the Docker tab after a successful run is the normal state. The next scheduled run will start it again.
