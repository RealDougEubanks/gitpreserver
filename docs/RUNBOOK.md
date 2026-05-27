<!--
doc: RUNBOOK
last-refreshed: 2026-05-27
generated-by: doc-refresh skill
-->

# Runbook — GitPreserver

> **You were just paged. Start here.**

---

## Is the service alive?

This only applies to **daemon mode**. One-shot mode exits after each run — a stopped container is normal.

```bash
# Health check (daemon mode)
curl -sf http://localhost:6033/healthz | jq .
```

Expected healthy response:

```json
{
  "status": "ok",
  "last_run": "2026-05-22T02:00:01Z",
  "last_result": "success",
  "schedule": "0 2 * * *"
}
```

HTTP 200 = healthy. HTTP 503 = last run failed. No response = container is down.

```bash
# Tail the last 50 log lines (daemon mode)
docker compose logs --tail=50 daemon

# Or if you redirect cron output to a file
tail -50 /var/log/gitpreserver.log
```

---

## Service overview

| Property | Value |
|----------|-------|
| Default port (daemon mode) | `6033` (set by `GITPRESERVER_WEB_PORT`) |
| Health endpoint | `GET /healthz` |
| Config endpoint | `GET /config` (sensitive values redacted) |
| Log location | `/var/log/gitpreserver.log` (if cron-redirected) or `docker compose logs daemon` |
| Backup output | `./backups/YYYY-MM-DD/` (or `GITPRESERVER_HOST_BACKUP_DIR`) |
| Lock file | `.gitpreserver.lock` in the project root (one-shot mode) |
| Image | `dougeubanks/gitpreserver` (Docker Hub) |

---

## Start / stop / restart

### One-shot mode (default)

```bash
# Run a backup now
./run-backup.sh

# Dry run — validates config, writes nothing
./run-backup.sh --dry-run

# Local backup only, no rclone
./run-backup.sh /path/to/backups --no-sync
```

### Daemon mode

```bash
# Start
docker compose up -d daemon

# Stop gracefully
docker compose stop daemon

# Restart
docker compose restart daemon

# View live logs
docker compose logs -f daemon
```

> **SECURITY:** If restarting after a suspected token compromise or security incident, do NOT restart in place.
> Rotate the PAT first (`GITPRESERVER_TOKEN`), update `.env`, then restart.

---

## Verify a backup succeeded

```bash
# List today's snapshot
ls backups/$(date -u +%Y-%m-%d)/repos/

# Verify a specific repo clone is intact
git --git-dir=backups/$(date -u +%Y-%m-%d)/repos/REPO_NAME.git log --oneline -5

# Check object integrity
git --git-dir=backups/$(date -u +%Y-%m-%d)/repos/REPO_NAME.git fsck
```

---

## Known failure modes

| Symptom | Root cause | Fix |
|---------|-----------|-----|
| `ERROR: GITPRESERVER_TOKEN is not set` | `.env` not found or variable blank | Copy `config/.env.example` to `.env` and set `GITPRESERVER_TOKEN` |
| `ERROR: GITPRESERVER_USERNAME is not set` | Username blank in `.env` | Set `GITPRESERVER_USERNAME` in `.env` |
| `Permission denied` writing to `/backups` | Container UID doesn't match host directory ownership | Set `PUID=$(id -u)` and `PGID=$(id -g)` in `.env` |
| Container exits with code 75 | Another backup run is already in progress (flock) | Wait for the current run to finish; exit code 75 means "try again later" |
| `rclone: command not found` or sync stage fails | rclone.conf missing or remote misconfigured | Run `./run-backup.sh --no-sync` to confirm mirror/metadata work, then fix rclone config |
| `HTTP 401` from GitHub API | PAT expired or revoked | Rotate the token at GitHub → Settings → Developer settings → Personal access tokens, update `GITPRESERVER_TOKEN` in `.env` |
| `HTTP 403` from GitHub API | PAT lacks required scopes | Recreate the token with Contents + Metadata + Issues + Pull requests (Read) |
| Web UI not reachable on port 6033 | Container not in daemon mode, or port not published | Confirm `GITPRESERVER_MODE=daemon` in `.env` and that `-p 6033:6033` is set |
| Last backup shows `failed` in `/healthz` | Backup stage errored | Check `docker compose logs daemon` or `/var/log/gitpreserver.log` for the specific stage that failed |

---

## Environment variables

> **SECURITY:** Never log, print, or commit these values. Rotate immediately if exposed.

See [`docs/ENV_VARS.md`](ENV_VARS.md) for the full reference.

The minimum required set:

| Variable | Description | Where to get it |
|----------|-------------|-----------------|
| `GITPRESERVER_TOKEN` | GitHub PAT | GitHub → Settings → Developer settings → Personal access tokens |
| `GITPRESERVER_USERNAME` | GitHub username or org to back up | Your GitHub profile |

---

## Rollback

```bash
# See recent releases
git log --oneline --decorate -10

# Roll back to a previous image tag
docker pull dougeubanks/gitpreserver:v1.2.3
# Update docker-compose.yml image: tag, then:
docker compose up -d daemon
```

---

## Escalation

If a backup has not completed in over 24 hours:

1. Check `/healthz` and `docker compose logs daemon`.
2. Confirm the PAT has not expired.
3. Check [GitHub Status](https://www.githubstatus.com/) — GitHub outages will block mirror-clone.
4. File an issue at [github.com/RealDougEubanks/gitpreserver/issues](https://github.com/RealDougEubanks/gitpreserver/issues).
