# What is not backed up

GitPreserver backs up git history, branches, tags, and metadata (issues, PRs, releases). It does not — and in most cases cannot — back up platform-specific configuration.

This is not a limitation to fix later. Some of these items are intentionally not exportable (secrets). Others require separate tooling. Document them manually in a password manager or wiki.

---

## GitHub-specific items

| Item | Why it's missing | What to do |
|---|---|---|
| **Actions Secrets** | Not accessible via the GitHub API by design | Store in Bitwarden. Export the secret *names* (not values) using `gh secret list` as a reference. |
| **Actions Environment secrets** | Same as above | Document environment names and the secrets they contain in Bitwarden. |
| **Actions Environment configuration** | Protection rules, required reviewers, deployment branches | Screenshot or document manually. Export via `gh api repos/{owner}/{repo}/environments` — roadmap item. |
| **GitHub Apps installed on the repo** | Platform-specific, no export API | Note the app name, slug, and permission set. |
| **OAuth app authorizations** | Account-level, not per-repo | Document which apps have access. |
| **Branch protection rules** | API-readable but not stored in git | Export via `gh api repos/{owner}/{repo}/branches/{branch}/protection` — roadmap item. |
| **GitHub Pages configuration** | Custom domain, enforce HTTPS, build source | Document custom domain and build settings. |
| **Rulesets** | Repository or organization rulesets | Export via `gh api repos/{owner}/{repo}/rulesets`. |
| **Collaborator access** | Users and their permission levels | Export via `gh api repos/{owner}/{repo}/collaborators`. |
| **Deploy keys** | Public keys granted push access | Document the key descriptions and their access levels. |
| **Webhooks** | URL, events, and secrets | Export via `gh api repos/{owner}/{repo}/hooks`. |
| **GitHub Discussions** | Not backed up in Phase 1 | No current mitigation — on the roadmap. |
| **GitHub Gists** | Separate API, not cloned by ghorg | Manually clone important gists. |
| **GitHub Pages site** | The generated static site, not the source | The source is in the repo. The generated output is reproducible. |

---

## Generic git platform items

| Item | Why it's missing | What to do |
|---|---|---|
| **CI/CD runner configuration** | Platform-specific (Actions, Pipelines, GitLab CI) | Document runner labels, environments, and required capabilities. |
| **Repository settings** | Default branch, merge strategies, PR settings | Screenshot or export via platform API. |
| **Project boards / Milestones** | Not in Phase 1 metadata export | Roadmap item. |
| **Wiki pages** | Wikis are separate git repos | Clone the wiki separately: `git clone https://github.com/user/repo.wiki.git` |
| **Packages / Container Registry** | Large binary artifacts | Back up separately with rclone or a dedicated registry mirror tool. |
| **LFS objects** | Large File Storage objects are not cloned by default | See ghorg's `--include-git-lfs` flag (roadmap). |

---

## Practical checklist

Before you depend on GitPreserver as your only safety net, document the following in a Bitwarden secure note or team wiki:

- [ ] All Actions secrets (names only — values must be in Bitwarden separately)
- [ ] All environment configurations with protection rules
- [ ] Installed GitHub Apps and their permission sets
- [ ] Branch protection rules for each protected branch
- [ ] Any GitHub Pages custom domain and DNS configuration
- [ ] Deploy keys and their purposes
- [ ] Active webhooks and their endpoint URLs
- [ ] Collaborators and their access levels

This takes 30 minutes once per project and saves hours of reconstruction after an incident.
