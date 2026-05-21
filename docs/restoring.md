# Restoring from a backup

GitPreserver mirror-clones produce standard bare git repositories. Restoring is a two-step process: get the data back onto disk, then push it to a new remote.

---

## Step 1 — Get the backup onto disk

### If you didn't use remote sync

Your backups are already local in `./backups/YYYY-MM-DD/`.

### If you used remote sync without encryption

```bash
mkdir -p /restore
docker run --rm \
  -v "$(pwd)/rclone/rclone.conf:/root/.config/rclone/rclone.conf:ro" \
  -v /restore:/restore \
  dougeubanks/gitpreserver \
  rclone sync b2-remote:gitpreserver-backups /restore
```

Replace `b2-remote` with your configured remote name.

### If you used remote sync with encryption

```bash
mkdir -p /restore
docker run --rm \
  -v "$(pwd)/rclone/rclone.conf:/root/.config/rclone/rclone.conf:ro" \
  -v /restore:/restore \
  dougeubanks/gitpreserver \
  rclone sync gitpreserver-crypt: /restore
```

This decrypts and downloads in one pass. You need `rclone.conf` with the crypt remote and the correct passphrase.

---

## Step 2 — Restore a repo to a new remote

Each `.git` directory in `repos/` is a bare mirror clone. Push it to a new host with:

```bash
cd /restore/2026-05-21/repos/your-repo.git

git remote add new-origin https://github.com/YOUR_USERNAME/your-repo.git
# or GitLab, Bitbucket, Gitea, etc.

git push --mirror new-origin
```

`git push --mirror` pushes all refs: branches, tags, and notes. The destination repository must exist and be empty (or you must force-push, which will overwrite history).

### Create the destination repo first

On GitHub:
```bash
gh repo create YOUR_USERNAME/your-repo --private --source=.
```

Or create it manually in the UI, then push.

### Restoring all repos at once

```bash
RESTORE_DATE=2026-05-21
REPOS_DIR="/restore/${RESTORE_DATE}/repos"
NEW_HOST="https://gitlab.com/YOUR_USERNAME"

for repo_dir in "${REPOS_DIR}"/*.git; do
    repo_name=$(basename "${repo_dir}" .git)
    echo "Restoring ${repo_name}..."
    # Create the repo on the new host (GitLab example using API)
    # Then push
    git -C "${repo_dir}" remote add new-origin "${NEW_HOST}/${repo_name}.git"
    git -C "${repo_dir}" push --mirror new-origin
done
```

---

## Restoring metadata

Issues, pull requests, and releases are stored as JSON files alongside the repos:

```
backups/2026-05-21/metadata/
├── your-repo/
│   ├── issues.json
│   ├── pull_requests.json
│   └── releases.json
└── another-repo/
    └── ...
```

These files are plain JSON arrays. You can:

- **Read them as-is** — they contain full issue and PR text, labels, assignees, and timestamps
- **Re-import them** using the target platform's API (re-import scripts are on the roadmap)
- **Archive them** alongside the restored repo for reference

---

## Verifying a mirror clone is intact

Before pushing to a new remote, verify the bare clone has all expected refs:

```bash
git --git-dir=/restore/2026-05-21/repos/your-repo.git log --oneline -10
git --git-dir=/restore/2026-05-21/repos/your-repo.git branch -a
git --git-dir=/restore/2026-05-21/repos/your-repo.git tag
```

And verify object integrity:

```bash
git --git-dir=/restore/2026-05-21/repos/your-repo.git fsck
```

---

## What cannot be restored

Some things are not in the backup. See [what-is-not-backed-up.md](what-is-not-backed-up.md) for the full list and mitigation recommendations.

The short version: GitHub Actions secrets, branch protection rules, CI/CD environment configs, and platform-specific settings are not exported. Document them separately.
