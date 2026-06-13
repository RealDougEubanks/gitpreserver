# Assumptions

This file records non-obvious design and security decisions, per the Golden Rules in `CLAUDE.md`.
New assumptions are appended at the bottom — do not rewrite history.

Each entry uses the format:

> **Assumption:** one clear sentence
>
> **Why:** rationale
>
> **Recorded by:** name (agent or human)
>
> **Date:** YYYY-MM-DD

---

## Container runs as a fixed non-root user (UID/GID 1000) by default; PUID/PGID adjust at runtime

**Assumption:** The image starts as root for a few hundred milliseconds so `docker/entrypoint.sh` can `usermod`/`groupmod` the `gitpreserver` user to match `PUID`/`PGID` env vars, `chown` the writable mounts, then `exec gosu gitpreserver:gitpreserver "$@"`. The workload — ghorg, gh, rclone — never runs as root. Default PUID/PGID are 1000/1000; unRAID convention is 99/100 (`nobody:users`).

**Why:** Least-privilege execution per Golden Rules — the long-running workload must not be root. Runtime PUID/PGID handling is required for unRAID and Synology ergonomics; their conventions assume containers honor those env vars (linuxserver.io pattern). A buildtime-only UID would force every user to either rebuild the image locally or chown every shared path. Capabilities are dropped to `CHOWN, FOWNER, SETUID, SETGID` — the minimum the entrypoint needs — with `no-new-privileges:true` set so the entrypoint cannot escalate beyond what the kernel grants on launch.

**Recorded by:** Claude (feature/phase1-mvp)
**Date:** 2026-05-21

---

## Local snapshots are not encrypted; only the rclone destination is

**Assumption:** Files under `${GITPRESERVER_BACKUP_DIR}` on the host are written in cleartext. Encryption only kicks in when `GITPRESERVER_ENCRYPT=true` and rclone syncs through a `crypt` remote.

**Why:** Local snapshots need to be readable for restore drills, retention pruning, and inspection without booting an rclone process. Users who require local-at-rest encryption should encrypt the underlying volume at the OS layer (LUKS, ZFS native encryption, APFS) — documenting that as a runtime concern keeps the application surface simple and the failure modes obvious.

**Recorded by:** Claude (feature/phase1-mvp)
**Date:** 2026-05-21

---

## Tokens are passed to subprocesses only via environment variables

**Assumption:** `GITPRESERVER_TOKEN` is exposed to `ghorg` and `gh` via their documented env vars (`GHORG_GITHUB_TOKEN`, `GHORG_GITLAB_TOKEN`, `GHORG_BITBUCKET_TOKEN`, `GHORG_GITEA_TOKEN`, `GH_TOKEN`). It is never passed as a CLI flag, written to disk, or logged.

**Why:** CLI flags appear in `/proc/<pid>/cmdline` and `ps` output, which are world-readable on most Linux systems. Env vars are visible only to the process and its parent.

**Recorded by:** Claude (feature/phase1-mvp)
**Date:** 2026-05-21

---

## Username and repo names are validated against `^[A-Za-z0-9._-]+$`

**Assumption:** Before `GITPRESERVER_USERNAME` or any discovered repo name is used in a path, CLI argument, or API call, it must match the regex `^[A-Za-z0-9._-]+$`. Anything else is rejected (username) or skipped with a warning (repo name).

**Why:** GitHub, GitLab, Bitbucket, and Gitea all restrict account and repo names to this character set or a subset of it. Validating up front is cheap insurance against argument injection and path traversal if a remote API ever returns an unexpected name.

**Recorded by:** Claude (feature/phase1-mvp)
**Date:** 2026-05-21

---

## `run-backup.sh` enforces single-run via `flock`

**Assumption:** Concurrent invocations of `run-backup.sh` are unsafe — the same snapshot directory would be written by two pipelines. The wrapper re-execs itself under `flock -n` on a lock file in the script directory; a second invocation exits with code 75 (EX_TEMPFAIL).

**Why:** Cron, systemd timers, and Synology Task Scheduler all schedule by wall clock. A long-running mirror that overlaps the next scheduled run would otherwise produce a partially-written or interleaved snapshot. Exit code 75 signals "try again later" without flagging a hard failure to cron mail handlers.

**Recorded by:** Claude (feature/phase1-mvp)
**Date:** 2026-05-21

---

## `--no-sync` runs retention via the `mirror` service, not `sync`

**Assumption:** When the user passes `--no-sync`, the wrapper invokes `docker compose run --rm --entrypoint sync.sh mirror` to run retention pruning, instead of starting the `sync` service. This deliberately bypasses tini as PID 1 inside the container.

**Why:** The `sync` service in `docker-compose.yml` bind-mounts `rclone.conf` read-only. A user running a local-only backup may not have configured rclone at all, so requiring that file to exist would break the use case. The `mirror` service shares the same image but has no rclone.conf mount. Running `sync.sh` under it with `GITPRESERVER_RCLONE_REMOTE=` exercises only the retention-prune path, which is a short-lived synchronous operation that doesn't need tini's reaping or signal-forwarding behavior.

**Recorded by:** Claude (feature/phase1-mvp)
**Date:** 2026-05-21

---

## All log timestamps are UTC

**Assumption:** Every log line emitted by GitPreserver scripts uses `date -u +%Y-%m-%dT%H:%M:%SZ`.

**Why:** Backups run on hosts in many time zones (NAS in a basement, laptop while traveling, cloud VM in a different region). Mixing local time in logs makes incident timelines hard to reconstruct. UTC is unambiguous and matches the format rclone and most cloud platforms use.

**Recorded by:** Claude (feature/phase1-mvp)
**Date:** 2026-05-21

---

## Web UI token auto-generates if unset and gates both `POST /run` and `GET /config`

**Assumption:** If `GITPRESERVER_WEB_TOKEN` is unset, the web server generates a random token at startup and prints it once to stderr. That token changes on every restart unless the operator sets it explicitly. The bearer token guards `POST /run` and also `GET /config`, since the config view exposes the active environment. A `POST` with no `Content-Length` header returns 411; a request with no `Origin` header is allowed through (token auth still applies), so command-line clients like curl work.

**Why:** A daemon-mode container with a trigger endpoint needs auth out of the box — a blank default would leave the run trigger open to anyone who can reach the port. Auto-generating and logging the token keeps the zero-config path safe while letting operators pin a stable value. Requiring `Content-Length` lets the handler bound the body before reading it. The Origin check is a CSRF defense for browsers; absence of Origin is normal for non-browser clients, so it falls back to token auth rather than rejecting.

**Recorded by:** Claude (immediate-todo sweep)
**Date:** 2026-06-11

---

## Webhook URLs must be https unless insecure delivery is explicitly opted into

**Assumption:** `backup/notify.sh` accepts `https://` webhook URLs unconditionally and `http://` only when `GITPRESERVER_WEBHOOK_ALLOW_INSECURE=true`. Any other scheme is rejected. Webhook delivery failures (timeout, HTTP 4xx/5xx, connection error) are logged as warnings and never fail the backup pipeline.

**Why:** Notification payloads carry the username, host type, and run status; sending them over plain http exposes that in transit. The insecure opt-in exists for LAN ntfy instances where TLS is impractical. Notifications are a side channel — a backup that completed successfully must not be reported as failed because Slack was briefly unreachable, so delivery errors stay non-fatal.

**Recorded by:** Claude (immediate-todo sweep)
**Date:** 2026-06-11

---

## `sync.sh` continues past a failing remote and reports partial failure out of band

**Assumption:** When `GITPRESERVER_RCLONE_REMOTE` lists multiple remotes, `sync.sh` syncs each one independently. A remote that fails is logged and recorded, but the loop continues to the remaining remotes. Local retention pruning always runs afterward, regardless of any sync failure. If any remote failed, the script exits non-zero and writes the comma-separated failed-remote list to `<backup_dir>/.gitpreserver-failed-remotes` for the notification layer to read.

**Why:** A single broken destination (expired key, network blip) should not stop backups reaching the others, and it should not block retention from reclaiming local disk. The exit code lets cron and the daemon flag the run as a partial failure. A status file is the least-coupled way to hand the failed list to `notify.sh`, which runs as a separate process.

**Recorded by:** Claude (immediate-todo sweep)
**Date:** 2026-06-11

---

## Bitbucket credentials are passed via a 0600 `curl --config` temp file

**Assumption:** Bitbucket metadata calls write credentials to a temporary `curl --config` file with mode 0600, removed on `EXIT`, rather than passing them on the command line. A Bitbucket curl exit code of 22 (HTTP 4xx, e.g. a disabled issue tracker) is treated as legitimately empty. Any other non-zero curl exit is a real failure and produces a `.partial` file instead of a complete-looking JSON document.

**Why:** Command-line credentials show up in `/proc/<pid>/cmdline` and `ps`; a 0600 config file keeps them out of the process list and off shared visibility. A disabled tracker returning 4xx is an expected, benign state — writing empty data there is correct — but a transport or auth error must not masquerade as "this resource is empty," so it is marked partial and excluded from the snapshot.

**Recorded by:** Claude (immediate-todo sweep)
**Date:** 2026-06-11

---

## The `gh` request timeout is best-effort; HTTP calls use explicit `--max-time`

**Assumption:** `gh` invocations are wrapped with `timeout`/`gtimeout` (60s) when one is present on the host, and run unbounded otherwise. Direct HTTP calls to Bitbucket and GitLab use curl `--max-time 30`.

**Why:** macOS dev hosts ship without GNU coreutils, so `timeout`/`gtimeout` may be absent; failing the run just because the timeout binary is missing would be worse than running unbounded on those hosts. In production containers coreutils is present, so the wrap takes effect. The curl `--max-time` is built into curl itself, so it applies everywhere.

**Recorded by:** Claude (immediate-todo sweep)
**Date:** 2026-06-11

---

## `GITPRESERVER_SCHEDULE` is validated against a strict cron grammar before use

**Assumption:** Before it is written to the supercronic crontab, `GITPRESERVER_SCHEDULE` must be either five numeric/operator fields or an `@`-shortcut. Day and month names (MON, JAN) are not accepted — use the numeric equivalents.

**Why:** The schedule value reaches a generated crontab and from there a command line, so an unvalidated value is a command-injection vector. A strict numeric grammar is simple to verify and rejects anything unexpected. Name aliases were excluded to keep the validator small and unambiguous; numeric fields cover every schedule.

**Recorded by:** Claude (immediate-todo sweep)
**Date:** 2026-06-11

---

## `GITPRESERVER_HOST_URL` is validated against a strict URL pattern

**Assumption:** `GITPRESERVER_HOST_URL` must match `^https?://host[:port][/path]` before use. Userinfo (`user:pass@`) and query strings are rejected.

**Why:** The host URL is passed to git tooling and HTTP clients. Allowing embedded userinfo or query strings widens the attack surface (credential leakage in logs, request smuggling) for no legitimate gain — a self-hosted host base URL needs only scheme, host, optional port, and optional path.

**Recorded by:** Claude (immediate-todo sweep)
**Date:** 2026-06-11

---

## All scripts emit logfmt to stderr with a shared run_id

**Assumption:** Every script emits structured logfmt lines to stderr in the shape `ts level component run_id msg`. The `run_id` is shared across stages via an exported environment variable so all lines from one pipeline run correlate. Logs were moved from stdout to stderr to comply with CLAUDE.md.

**Why:** stdout is reserved for actual command output and machine-readable results; mixing logs into it corrupts pipes and captured output. A shared `run_id` lets an operator stitch together mirror, metadata, sync, and notify lines from a single run across separate processes.

**Recorded by:** Claude (immediate-todo sweep)
**Date:** 2026-06-11

---

## Dockerfile tool versions are pinned to real, upstream-verified SHA256 checksums

**Assumption:** The Dockerfile pins ghorg 1.11.11, gh 2.94.0, rclone 1.74.3, and supercronic 0.2.46 (latest stable as of 2026-06-12), each with genuine per-architecture SHA256 checksums. rclone/gh/ghorg hashes come from upstream release checksum files (`SHA256SUMS`, `checksums.txt`); supercronic publishes no checksum file, so its two hashes were computed directly from the released `supercronic-linux-amd64`/`-arm64` binaries. When bumping any version, refresh its two SHA256 ARGs from the same sources — the `sha256sum --check --strict` steps enforce them at build time.

**Why:** Pinning a verified checksum is the protection against a tampered or swapped download. The earlier revision shipped `REPLACE_WITH_REAL_SHA256` placeholders because the values could not be obtained offline; they have since been resolved from authoritative upstream sources (reading exact bytes, not transcribed), so the build now succeeds against real artifacts.

**Recorded by:** Claude (immediate-todo sweep)
**Date:** 2026-06-12

---

## Synology distribution targets manual install + Community Package Hub, not SynoCommunity (for now)

**Assumption:** GitPreserver ships its Synology package via the hand-rolled `synology/build-spk.sh` tarball, installed through DSM Package Center → Manual Install, and (optionally) listed on Community Package Hub. A full SynoCommunity submission — which requires porting the package to their `spksrc` build framework — is deliberately deferred.

**Why:** spksrc is a substantial build-system investment (cross-compilation toolchain, framework conventions, review cycle) that is not justified while the package is a thin `docker run` wrapper. Manual install and CPHub deliver the same artifact to users today with far less maintenance burden. This is a reversible call: if user demand for a one-click SynoCommunity listing grows, revisit the spksrc port. Documented here so the absence of a SynoCommunity package is understood as a choice, not an oversight.

**Recorded by:** Claude (immediate-todo sweep)
**Date:** 2026-06-12
