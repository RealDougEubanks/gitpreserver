# Setup — unRAID

This guide covers installing GitPreserver on an unRAID server.

> **Status:** The Community Applications template is scaffolded but not yet submitted to the CA repository. Until it is available in CA, use the manual setup below.

---

## Prerequisites

- unRAID 6.10+
- Community Applications plugin installed
- Docker enabled

---

## Option A — Community Applications (coming soon)

Once the template is submitted and approved:

1. Open **Apps** in the unRAID UI
2. Search for **GitPreserver**
3. Click **Install** and fill in the required fields:
   - Personal Access Token
   - Username or org
   - Host type (GitHub / Bitbucket / GitLab / Gitea)
   - Backup path on host (default: `/mnt/user/appdata/gitpreserver`)
4. Configure the rclone remote and encryption in the generated `.env` file if needed
5. Use the **User Scripts** plugin or the CA scheduler to run on a schedule

---

## Option B — Manual Docker setup (available now)

### 1. Open a terminal on the unRAID host

Use the built-in terminal in the unRAID UI or SSH:

```bash
ssh root@your-unraid-ip
```

### 2. Clone GitPreserver

```bash
mkdir -p /mnt/user/appdata/gitpreserver
cd /mnt/user/appdata/gitpreserver
git clone https://github.com/dougeubanks/gitpreserver.git .
```

### 3. Configure

```bash
cp config/.env.example .env
vi .env
```

Set at minimum:

```bash
GITPRESERVER_TOKEN=ghp_your_token_here
GITPRESERVER_USERNAME=your_github_username
GITPRESERVER_BACKUP_DIR=/mnt/user/gitpreserver-backups
```

### 4. Create the backup share

In the unRAID UI, go to **Shares** and create a new share called `gitpreserver-backups`, or create the directory manually:

```bash
mkdir -p /mnt/user/gitpreserver-backups
```

### 5. Build and test

```bash
cd /mnt/user/appdata/gitpreserver
docker compose build
GITPRESERVER_DRY_RUN=true ./run-backup.sh
./run-backup.sh
```

### 6. Schedule with User Scripts

1. Install the **User Scripts** plugin from Community Applications
2. Open **Settings → User Scripts → Add New Script**
3. Name it `GitPreserver Backup`
4. Click the gear icon → **Edit Script**
5. Paste:
   ```bash
   #!/bin/bash
   cd /mnt/user/appdata/gitpreserver && ./run-backup.sh
   ```
6. Click **Save**
7. Set the schedule using the cron expression from `GITPRESERVER_SCHEDULE` (default: `0 2 * * 0`)

---

## Paths reference

| What | Path |
|---|---|
| Project files | `/mnt/user/appdata/gitpreserver/` |
| Backup snapshots | `/mnt/user/gitpreserver-backups/` |
| `.env` | `/mnt/user/appdata/gitpreserver/.env` |
| `rclone.conf` | `/mnt/user/appdata/gitpreserver/rclone/rclone.conf` |

---

## Notes

- unRAID's Docker implementation does not persist images across reboots by default unless you store them on the array or cache. The image will be pulled again on the next start if it was on a temporary volume.
- Point `GITPRESERVER_BACKUP_DIR` at a path on the array (`/mnt/user/...`) not on the RAM disk or a tmpfs mount.
- If you use the Mover to tier data between cache and array, GitPreserver's backup directory will be moved automatically if you configure it as a share on the array. This is expected behavior.
