<!--
doc: SECURITY
last-refreshed: 2026-05-27
generated-by: doc-refresh skill
-->

# Security Policy

## Reporting a Vulnerability

> **SECURITY: Do NOT open a public GitHub issue for a security vulnerability.**
> Public disclosure before a fix is available puts all users at risk.

Report privately via [GitHub Security Advisories](https://github.com/RealDougEubanks/gitpreserver/security/advisories/new).

Expected acknowledgment: within 48 hours.

---

## Sensitive Data This Project Handles

| Data | Where it lives | How it is protected |
|------|---------------|---------------------|
| GitHub PAT (`GITPRESERVER_TOKEN`) | `.env` / container env var | Passed to subprocesses via env only — never written to disk or logged. See `docs/assumptions.md`. |
| rclone remote credentials | `rclone/rclone.conf` | Mounted read-only (`:ro`) into the container. Never committed — in `.gitignore`. |
| Encryption passphrase (`GITPRESERVER_CRYPT_PASS`) | `.env` / `rclone.conf` | Stored in `rclone.conf` in obscured form. Raw value must be stored in a password manager. |
| Cloud storage keys (B2, S3, R2, etc.) | `rclone/rclone.conf` | Same as above. |
| MEGA / SMB passwords | `rclone/rclone.conf` | Stored in rclone obscured form. |

---

## Credential and Secret Rules

> **SECURITY:** All secrets must be in environment variables or `rclone.conf` (itself excluded from version control).
> Never commit secrets. Rotate immediately if exposed.

1. `.env` is in `.gitignore`. Never force-commit it.
2. `rclone/rclone.conf` is in `.gitignore`. Never force-commit it.
3. Use a dedicated PAT with the minimum required scopes — not a personal admin token.
4. Set a PAT expiry. Rotate it before it expires. Store the new value in Bitwarden before updating `.env`.
5. If an encryption passphrase is lost, the backup is permanently unrecoverable. There is no key escrow.

---

## Container Security Controls

The container applies defense-in-depth:

- Runs as a non-root user (`gitpreserver`, UID 1000 by default) after a brief entrypoint setup phase.
- `no-new-privileges:true` — the workload cannot gain capabilities beyond what the kernel grants at launch.
- All Linux capabilities dropped except `CHOWN`, `FOWNER`, `SETUID`, `SETGID` — the minimum the entrypoint needs to remap UID/GID at runtime.
- `rclone.conf` is always mounted read-only.
- Tokens are passed to `ghorg` and `gh` via their documented environment variables (`GHORG_GITHUB_TOKEN`, `GH_TOKEN`), never as CLI flags (which appear in `ps` output).

See `docs/assumptions.md` for full rationale.

---

## Web UI (Daemon Mode)

> **SECURITY:** The web UI on port 6033 has no authentication by default.

- Do not expose port 6033 to the public internet.
- Run it on a private LAN or behind a reverse proxy with HTTP Basic Auth (nginx, Caddy, Traefik).
- The `/config` endpoint redacts sensitive env vars (`***`) but lists their names. Treat it as internal-only.

---

## Dependency Security

Run the secret scanner before every release:

```bash
# Scan for secrets in git history
docker run --rm -v "$(pwd):/repo" zricethezav/gitleaks:latest detect --source /repo
```

The CI pipeline runs gitleaks on every push and PR via `.github/workflows/lint.yml`.

---

## Supported Versions

Only the latest release receives security fixes. There is no LTS branch.

| Version | Supported |
|---------|-----------|
| Latest  | Yes       |
| Older   | No        |
