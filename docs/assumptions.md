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

## Container runs as a fixed non-root user (UID/GID 1000)

**Assumption:** The runtime image runs as `gitpreserver` (UID 1000, GID 1000) by default. Host bind mounts (`./backups`, `./rclone/rclone.conf`) must be readable and writable by that UID, or the user must override with the `PUID`/`PGID` build args or `user:` directive in `docker-compose.yml`.

**Why:** Least-privilege execution per Golden Rules. Running as root inside a container that touches user-owned data and writes a snapshot directory tree every night is unnecessary risk. UID 1000 matches the default first-user UID on Debian/Ubuntu/most desktop Linux, which is the common host environment.

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

## All log timestamps are UTC

**Assumption:** Every log line emitted by GitPreserver scripts uses `date -u +%Y-%m-%dT%H:%M:%SZ`.

**Why:** Backups run on hosts in many time zones (NAS in a basement, laptop while traveling, cloud VM in a different region). Mixing local time in logs makes incident timelines hard to reconstruct. UTC is unambiguous and matches the format rclone and most cloud platforms use.

**Recorded by:** Claude (feature/phase1-mvp)
**Date:** 2026-05-21
