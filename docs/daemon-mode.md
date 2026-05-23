# Daemon Mode & Web UI

By default GitPreserver runs in `oneshot` mode: it backs up once and exits. This works well with an external scheduler (cron, Synology Task Scheduler, unRAID User Scripts).

`daemon` mode keeps the container running permanently. It fires backups on an internal cron schedule and serves a lightweight web UI for status monitoring and manual triggers.

---

## Choosing a mode

| | `oneshot` (default) | `daemon` |
|---|---|---|
| Container lifecycle | Exits after each run | Runs continuously |
| Scheduling | External (cron, Task Scheduler) | Internal (`GITPRESERVER_SCHEDULE`) |
| Web UI | No | Yes — port 6033 by default |
| `restart: unless-stopped` | Not useful | Recommended |
| Suitable for | CI, NAS task schedulers, ad-hoc runs | Always-on Docker hosts, unRAID, VPS |

---

## Starting daemon mode

### docker compose

```bash
docker compose up daemon
```

The `daemon` service is defined in `docker-compose.yml` with `restart: unless-stopped`. It mounts the same backup volume and optional rclone config as the one-shot services.

### Plain docker run

```bash
docker run -d \
  --name gitpreserver \
  --restart unless-stopped \
  -e GITPRESERVER_MODE=daemon \
  -e GITPRESERVER_TOKEN=github_pat_… \
  -e GITPRESERVER_USERNAME=your_username \
  -e GITPRESERVER_SCHEDULE="0 2 * * *" \
  -v /path/to/backups:/backups \
  -p 6033:6033 \
  dougeubanks/gitpreserver
```

---

## Web UI

When running in daemon mode the container serves a web interface at:

```
http://<host>:6033
```

### Dashboard (`/`)

- Current backup status badge (idle / running / success / failed)
- Last run timestamp
- Active cron schedule
- Output from the most recent run
- **Run Now** button — triggers an immediate backup outside the schedule

### Health check (`/healthz`)

Returns JSON and an HTTP status code suitable for uptime monitors:

```json
{
  "status": "ok",
  "last_run": "2026-05-22T02:00:01Z",
  "last_result": "success",
  "schedule": "0 2 * * *"
}
```

- `200 OK` when the last result was success, idle, or no run yet
- `503 Service Unavailable` when the last run failed or errored

Point NodePing, UptimeRobot, or your monitoring tool at `http://<host>:6033/healthz`.

### Configuration (`/config`)

Returns JSON listing all active `GITPRESERVER_*` and `RCLONE_CONFIG_*` environment variables. Sensitive values (tokens, passwords, keys) are redacted to `***`.

---

## Schedule syntax

`GITPRESERVER_SCHEDULE` accepts standard five-field cron expressions:

```
┌───── minute  (0–59)
│ ┌───── hour    (0–23)
│ │ ┌───── day of month (1–31)
│ │ │ ┌───── month (1–12)
│ │ │ │ ┌───── day of week (0–6, Sunday=0)
│ │ │ │ │
0 2 * * 0   →  every Sunday at 02:00 UTC (default)
0 2 * * *   →  every day at 02:00 UTC
0 */6 * * * →  every 6 hours
```

All container timestamps are UTC. If you want local-time scheduling, set the `TZ` environment variable:

```bash
TZ=America/New_York
GITPRESERVER_SCHEDULE=0 2 * * *   # 02:00 Eastern
```

---

## rclone configuration via environment variables

`rclone.conf` is optional. rclone reads any remote's configuration from environment variables using the pattern:

```
RCLONE_CONFIG_<REMOTE>_<KEY>=value
```

Remote names are uppercased and hyphens become underscores. Example for Backblaze B2 with encryption:

```bash
# B2 storage backend
RCLONE_CONFIG_B2_TYPE=b2
RCLONE_CONFIG_B2_ACCOUNT=your_account_id
RCLONE_CONFIG_B2_KEY=your_app_key

# crypt remote layered on top of B2
RCLONE_CONFIG_MYCRYPT_TYPE=crypt
RCLONE_CONFIG_MYCRYPT_REMOTE=b2:gitpreserver-backups
RCLONE_CONFIG_MYCRYPT_FILENAME_ENCRYPTION=standard
RCLONE_CONFIG_MYCRYPT_DIRECTORY_NAME_ENCRYPTION=true
RCLONE_CONFIG_MYCRYPT_PASSWORD=<rclone obscure 'your-passphrase'>
RCLONE_CONFIG_MYCRYPT_PASSWORD2=<rclone obscure 'your-salt'>

# Point GitPreserver at those remotes
GITPRESERVER_RCLONE_REMOTE=b2
GITPRESERVER_ENCRYPT=true
GITPRESERVER_CRYPT_REMOTE=mycrypt
```

Generate the obscured password values once on any machine with rclone installed:

```bash
docker run --rm dougeubanks/gitpreserver rclone obscure 'your-passphrase'
docker run --rm dougeubanks/gitpreserver rclone obscure 'your-salt'
```

When `GITPRESERVER_RCLONE_CONFIG` is left blank, `docker-compose.yml` mounts `/dev/null` in place of `rclone.conf`, giving rclone an empty file to parse. Remote definitions come entirely from env vars.

---

## Security note

The web UI has no authentication by default. It is intended to run on a private LAN behind a firewall (home server, NAS, private VPN). Do not expose port 6033 directly to the public internet. If external access is required, put it behind a reverse proxy with HTTP Basic Auth (nginx, Caddy, Traefik).

---

## Environment variable reference

| Variable | Default | Description |
|---|---|---|
| `GITPRESERVER_MODE` | `oneshot` | `oneshot` or `daemon` |
| `GITPRESERVER_SCHEDULE` | `0 2 * * 0` | Cron expression (daemon mode) |
| `GITPRESERVER_WEB_PORT` | `6033` | Web UI port (daemon mode) |
| `GITPRESERVER_STATUS_FILE` | `/tmp/gitpreserver-status.json` | Path to the status JSON written after each run |
