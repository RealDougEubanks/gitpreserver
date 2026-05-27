# Setup — Synology DSM 7+

This guide covers installing GitPreserver on a Synology NAS running DSM 7.0 or later.

> **Status:** The Synology SPK package is buildable locally (see Option B below) but not yet submitted to SynoCommunity. Until it is available in Package Center, use the manual Docker setup or build the SPK from source.

---

## Prerequisites

- Synology NAS with DSM 7.0+ (x86_64 or ARM64)
- Docker installed from Package Center
- Docker running (Container Manager or legacy Docker package)
- SSH access to the NAS (for manual setup)

---

## Option A — Manual Docker setup (available now)

This is the recommended approach until the SPK is published.

### 1. Connect via SSH

Enable SSH in **Control Panel → Terminal & SNMP → Terminal**, then:

```bash
ssh admin@your-nas-ip
```

### 2. Clone GitPreserver

```bash
sudo mkdir -p /volume1/docker/gitpreserver
cd /volume1/docker/gitpreserver
sudo git clone https://github.com/RealDougEubanks/gitpreserver.git .
```

### 3. Configure

```bash
sudo cp config/.env.example .env
sudo vi .env
```

Set at minimum:

```bash
GITPRESERVER_TOKEN=ghp_your_token_here
GITPRESERVER_USERNAME=your_github_username
GITPRESERVER_BACKUP_DIR=/volume1/gitpreserver-backups
```

If you want remote sync, also configure `rclone/rclone.conf`. See [storage-backends.md](storage-backends.md).

### 4. Create the backup volume

```bash
sudo mkdir -p /volume1/gitpreserver-backups
```

### 5. Build and run

```bash
cd /volume1/docker/gitpreserver
sudo docker compose build
sudo ./run-backup.sh
```

### 6. Schedule with DSM Task Scheduler

1. Open **Control Panel → Task Scheduler**
2. Click **Create → Scheduled Task → User-defined script**
3. Set:
   - **Task name:** GitPreserver Backup
   - **User:** root
   - **Schedule:** your preferred schedule (e.g. weekly on Sunday at 02:00)
4. Under **Task Settings**, enter:
   ```bash
   cd /volume1/docker/gitpreserver && ./run-backup.sh >> /var/log/gitpreserver.log 2>&1
   ```
5. Click **OK**

---

## Option B — SPK package (build from source)

You can build and install the SPK directly without waiting for SynoCommunity listing.

### Build

On any machine with bash and tar:

```bash
git clone https://github.com/RealDougEubanks/gitpreserver.git
cd gitpreserver
./synology/build-spk.sh
# Output: synology/dist/gitpreserver-1.1.0-1.spk
```

### Install

1. Open **Package Center → Manual Install**
2. Upload `gitpreserver-1.1.0-1.spk`
3. Follow the wizard — it collects:
   - Git host (GitHub / Bitbucket / GitLab / Gitea)
   - Self-hosted URL (if applicable)
   - Username / org
   - Personal access token
   - Backup path
   - Schedule

Remote sync and encryption must be configured manually in the `.env` file at `/var/packages/gitpreserver/target/.env` after install. See [configuration.md](configuration.md) for all available variables.

### SynoCommunity (coming soon)

Once accepted, the install will be available directly from Package Center by adding `https://packages.synocommunity.com` as a package source.

---

## Paths reference

| What | Path |
|---|---|
| Project files | `/volume1/docker/gitpreserver/` |
| Backup snapshots | `/volume1/gitpreserver-backups/` |
| `.env` | `/volume1/docker/gitpreserver/.env` |
| `rclone.conf` | `/volume1/docker/gitpreserver/rclone/rclone.conf` |
| Log | `/var/log/gitpreserver.log` |

---

## Notes

- Synology DSM exposes a `date` binary that may not support `--iso-8601`. The backup scripts use `date +%Y-%m-%d` which works on BusyBox.
- ARM64 Synology models (e.g. DS220+) are supported. The Docker image builds for both amd64 and arm64.
- If you use the Synology Moments or Photos package, do not point `GITPRESERVER_BACKUP_DIR` at a shared folder managed by those packages.
