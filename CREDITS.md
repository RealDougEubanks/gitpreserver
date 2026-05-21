# Credits

GitPreserver stands on the shoulders of a lot of excellent open-source software. This file lists every third-party project we depend on, what it does for us, and the license it ships under. If you maintain any of these projects: thank you.

## Runtime — bundled inside the Docker image

These tools are installed in the image at `docker/Dockerfile` and run on every backup.

| Tool | Project | License | Role |
|---|---|---|---|
| ghorg | [gabrie30/ghorg](https://github.com/gabrie30/ghorg) | Apache-2.0 | Bulk mirror-cloning every repository in a GitHub / GitLab / Bitbucket / Gitea account. The `--backup` flag invokes `git clone --mirror` semantics — every branch, every tag, every ref. Without it, this project would be a hand-rolled API paginator with retry logic. |
| gh (GitHub CLI) | [cli/cli](https://github.com/cli/cli) | MIT | Authenticated calls against the GitHub REST API in `backup/metadata.sh`. We use `gh api --paginate` to export issues, pull requests, and releases as JSON sidecars. |
| rclone | [rclone/rclone](https://github.com/rclone/rclone) | MIT | All offsite sync. Every supported destination — Backblaze B2, AWS S3, Google Drive, OneDrive, MEGA, SMB, NFS, and 70+ more — is rclone underneath. `rclone crypt` provides the optional AES-256 encryption at rest. |
| tini | [krallin/tini](https://github.com/krallin/tini) | MIT | Tiny init for PID 1 inside the container. Handles signal forwarding and zombie reaping during long ghorg or rclone runs. |
| jq | [jqlang/jq](https://github.com/jqlang/jq) | MIT | JSON merging in `backup/metadata.sh`. `gh api --paginate` emits one JSON array per page; `jq -s 'add // []'` slurps them into a single valid array. |
| git | [git/git](https://github.com/git/git) | GPL-2.0 | The version control tool the entire project exists to back up. ghorg invokes `git clone --mirror` to produce bare snapshots of every repository. |
| Debian | [debian.org](https://www.debian.org/) | various — see [Debian Free Software Guidelines](https://www.debian.org/social_contract#guidelines) | `debian:bookworm-slim` is the base image. Provides bash, ca-certificates, curl, the apt ecosystem we install jq/tini/git from, and the kernel ABI the binaries above link against. |

## Development and CI — not shipped

These tools run during development and in `.github/workflows/lint.yml`. They are not present in the published image.

| Tool | Project | License | Role |
|---|---|---|---|
| bats-core | [bats-core/bats-core](https://github.com/bats-core/bats-core) | MIT | The unit-test runner under `tests/`. 30+ assertions covering input validation, dry-run pipelines, retention pruning, ghorg argument shape, and wrapper CLI behavior. |
| ShellCheck | [koalaman/shellcheck](https://github.com/koalaman/shellcheck) | GPL-3.0 | Static analysis of every shell script in the repo. Runs in CI at warning severity. |
| hadolint | [hadolint/hadolint](https://github.com/hadolint/hadolint) | GPL-3.0 | Static analysis of `docker/Dockerfile`. Caught the missing `SHELL ["/bin/bash", "-o", "pipefail", "-c"]` directive that would have masked install failures. |
| gitleaks | [gitleaks/gitleaks](https://github.com/gitleaks/gitleaks) | MIT | Secret-scanning across the full git history on every push. Required for a public OSS project of this shape. |

## Inspiration and prior art

- [github-backup](https://github.com/josegonzalez/python-github-backup) by Jose Diaz-Gonzalez — a Python alternative we considered before settling on ghorg. Worth knowing about.
- The "use rclone for everything" pattern is borrowed from countless self-hosted backup tools in the [awesome-selfhosted](https://github.com/awesome-selfhosted/awesome-selfhosted) ecosystem.

## License compatibility

GitPreserver is distributed under the [MIT License](LICENSE). All bundled runtime dependencies (Apache-2.0, MIT, GPL-2.0) are compatible with redistribution as part of an MIT-licensed Docker image. The GPL-2.0-licensed components (git) and GPL-3.0-licensed development tools (ShellCheck, hadolint) are invoked as standalone executables, not linked into our code, so their licenses do not propagate.

If you find an attribution gap here, please open an issue or a PR — we want this list to stay honest.
