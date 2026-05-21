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
