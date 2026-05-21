# Contributing to GitPreserver

Thanks for taking the time to contribute. This document covers how to report issues, propose features, and submit pull requests.

---

## Reporting bugs

Search [existing issues](https://github.com/dougeubanks/gitpreserver/issues) before opening a new one — your bug may already be tracked.

When filing a bug report, include:
- GitPreserver version (`git describe --tags`)
- Host OS and Docker version
- The git host type and phase (GitHub Phase 1, etc.)
- Relevant log output (redact tokens and credentials)
- What you expected to happen vs. what actually happened

Use the **Bug Report** issue template.

---

## Requesting features

Open a **Feature Request** issue and describe:
- The problem you're solving (not just the solution)
- Which platform(s) are affected
- Whether you'd like to implement it yourself

---

## Pull requests

1. **Fork** the repo and create a branch from `main`.
   - `feature/short-description` for new features
   - `fix/short-description` for bug fixes
2. Write your changes. Follow the code style below.
3. Run ShellCheck locally before pushing (see below).
4. Open a PR against `main`. Fill in the PR template.
5. One approval required to merge. For the initial period, the maintainer self-reviews.

Keep PRs focused. A PR that fixes one thing is easier to review than one that fixes five.

---

## Local development setup

You need:
- Docker and Docker Compose
- [ShellCheck](https://www.shellcheck.net/) (`brew install shellcheck` or `apt install shellcheck`)
- A GitHub token for integration testing (minimum `repo` + `read:user` scopes)

```bash
git clone https://github.com/dougeubanks/gitpreserver.git
cd gitpreserver
cp config/.env.example .env
# fill in GITPRESERVER_TOKEN and GITPRESERVER_USERNAME in .env

# Lint all scripts
shellcheck backup/*.sh run-backup.sh synology/scripts/*

# Dry-run a full backup cycle (no writes, no sync)
GITPRESERVER_DRY_RUN=true ./run-backup.sh
```

---

## Code style

GitPreserver's scripts are plain Bash. Keep them readable and auditable.

- Target `bash` (`#!/usr/bin/env bash`) with `set -euo pipefail` at the top of every script.
- Pass ShellCheck with no warnings at severity `warning` or above. Use `# shellcheck disable=SC...` only when the warning is a false positive — add a comment explaining why.
- Use `log()` for all output. Never `echo` directly to stdout in a script that may be redirected.
- Guard required variables with `: "${VAR:?message}"` at the top of the script.
- Prefer `[[ ]]` over `[ ]` for conditionals.
- No lines longer than 100 characters.
- Indent with 4 spaces — no tabs.
- Remove dead code, commented-out blocks, and debug `echo` statements before submitting.

---

## Testing

There is no automated test suite yet (tracked in the roadmap). When adding or changing a script:

1. Run it with `GITPRESERVER_DRY_RUN=true` first.
2. Run it against a test account with a small number of repos.
3. Verify output files are created in the expected directory structure.
4. Check that log output uses the `[gitpreserver]` prefix and ISO timestamps.

---

## Commit messages

Write commit messages in the imperative: "Add retention pruning" not "Added retention pruning."

Keep the subject line under 72 characters. If the change needs explanation, add a blank line and a body paragraph. Reference issue numbers where relevant (`Closes #42`).

---

## License

By contributing, you agree that your contributions will be licensed under the project's [MIT License](LICENSE).
