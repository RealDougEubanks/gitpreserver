# GitPreserver — To Do

Tracked improvements that are not yet scheduled for a specific release.
Move items to the relevant `[Unreleased]` CHANGELOG section when work begins.

---

## Security

### Automate binary version tracking with Renovate regex managers

**Priority:** High  
**Context:** The four tool binaries bundled in `docker/Dockerfile` — `ghorg`, `gh`, `rclone`, and `supercronic` — are downloaded via `curl` and pinned by version ARG. Dependabot cannot discover or bump curl-fetched assets, so CVEs in these binaries are only caught by Trivy and require manual version bumps and SHA256 updates.

**What to do:**  
Adopt [Renovate](https://docs.renovatebot.com/) alongside or instead of Dependabot and add `regexManagers` rules that match the `ARG *_VERSION=` lines in the Dockerfile. Renovate's regex manager can track GitHub releases for each tool and open PRs that update both the version ARG and the corresponding SHA256 ARG in one commit.

Example manager shape (one per tool):
```json
{
  "regexManagers": [
    {
      "fileMatch": ["docker/Dockerfile"],
      "matchStrings": ["ARG RCLONE_VERSION=(?<currentValue>[^\\n]+)"],
      "depNameTemplate": "rclone/rclone",
      "datasourceTemplate": "github-releases"
    }
  ]
}
```

The SHA256 ARGs would still need to be refreshed manually or via a companion script unless Renovate's `postUpgradeTasks` feature is used to run a checksum-fetch script as part of the PR.

**Workaround until done:**  
Run `docker/Dockerfile` binary versions through Trivy on every PR (already in CI). When Trivy flags a CVE with an available fix in one of these binaries, bump the version ARG and SHA256 ARGs manually as done for rclone 1.74.3 → 1.74.4 (CVE-2026-54572, 2026-09-09).
