# Contributing to panora-versioning-pipe

Thank you for your interest in contributing. This document covers how to set up a local development environment, test changes, and submit a pull request.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) — required to build and run the pipe
- [Make](https://www.gnu.org/software/make/) — for the development workflow targets
- [shellcheck](https://www.shellcheck.net/) — optional but recommended for linting (`brew install shellcheck`)

## Development Setup

1. Fork the repository and clone your fork:

   ```bash
   git clone https://github.com/your-username/panora-versioning-pipe.git
   cd panora-versioning-pipe
   ```

2. Build the Docker image locally:

   ```bash
   make build
   ```

3. Open an interactive shell inside the container to explore or debug:

   ```bash
   make shell
   ```

## Local Testing

For day-to-day development, exercise the pipe via the automated unit tests (Dockerised bats suite) and the integration tests that drive real repositories on GitHub and Bitbucket:

```bash
make test                      # bats unit tests in Docker
make test-integration          # GitHub integration scenarios (requires gh CLI)
make test-integration-bitbucket # Bitbucket integration scenarios (requires BB_TOKEN)
```

See `docs/tests/README.md` for the full test-coverage reference.

For manual spot-checks you can also drive the container directly. `make shell` drops you into an interactive shell with the current directory mounted at `/workspace`, where you can export the generic `VERSIONING_*` variables and run `/pipe/pipe.sh` by hand:

```bash
make shell

# inside the container
export VERSIONING_PR_ID=1
export VERSIONING_BRANCH=feature/my-branch
export VERSIONING_TARGET_BRANCH=main
export VERSIONING_COMMIT=$(git rev-parse HEAD)
/pipe/pipe.sh
```

Place a `.versioning.yml` in the directory you run from to test different configurations. See `examples/configs/` for ready-to-use config examples.

## Linting

Run shellcheck on all shell scripts:

```bash
make lint
```

All scripts must pass shellcheck with no errors before submitting a PR.

## Code Style

- Shell scripts use POSIX `sh` (`#!/bin/sh`) unless Bash-specific features are strictly required.
- Follow the existing pattern: `set -e` at the top, explicit `|| true` for optional failures.
- Use `log_info`, `log_error`, `log_success` from `scripts/lib/common.sh` — do not use bare `echo` for status messages.
- Keep functions short and single-purpose.
- Comments must be in English.

## Commit Format

This repository uses **ticket format** by default. Commits should follow one of these formats:

**Ticket format** (if your team uses a ticket tracker):
```
PROJ-123 - feat: add support for custom tag prefix
PROJ-456 - fix: handle empty commit list edge case
```

**Conventional commits** (if no ticket system):
```
feat: add support for custom tag prefix
fix: handle empty commit list edge case
```

Valid types: `feat`, `fix`, `docs`, `test`, `chore`, `refactor`, `perf`, `ci`, `build`, `style`, `revert`.

The last commit in a PR must include a type. Intermediate commits may be untyped (merge commits, fixups).

## Commit Message Hygiene

GitHub Actions scans commit messages for workflow-skip directives like `[skip ci]`, `[ci skip]`, `[no ci]`, `[skip actions]`, and `[actions skip]`. The match is a **plain substring check** — it does not distinguish a directive from prose that happens to include the same characters. If any of these strings appears anywhere in the subject or body of a push commit, every workflow on that push is silently skipped.

This matters in two very different places:

1. **Intentional — the pipe itself**. `scripts/changelog/update-changelog.sh` deliberately writes `[skip ci]` in the CHANGELOG commit subject so that the atomic tag-and-changelog push from `tag-on-merge.yml` does not re-trigger itself into an infinite loop. This is the pipe's internal circuit breaker and must never be removed.
2. **Accidental — in PR commit messages**. When you describe the pipe's behavior in a commit message or PR body (for example, explaining how the atomic push works), do NOT paste the literal directive string as prose. GitHub will substring-match it, skip the workflow on merge, and the PR will land on main without triggering `tag-on-merge.yml` — no tag, no CHANGELOG, no release.

**Safe alternatives when documenting the behavior in commits or PR bodies**:

- `skip-ci` (with a dash)
- `"skip ci"` (in quotes, without the square brackets)
- "the CI skip directive"
- "the atomic push marker"
- "the workflow-skip pragma"

**Incident context**: PR #34 was merged to `main` without a tag because its commit body contained the literal substring as descriptive prose. GitHub's substring match skipped `tag-on-merge.yml`, leaving the change untagged. The fix was to bundle PR #34 into the next release (PR #35). If you hit the same gotcha, open a follow-up PR whose merge triggers the missed tagging — do not try to re-run the skipped workflow manually.

File contents (READMEs, YAML comments, shell scripts) are **not** scanned — only commit messages and the subject line of the HEAD commit on a push. You can freely write the literal directive inside a file like this `CONTRIBUTING.md` for educational purposes. Just keep it out of the git log.

### Automated enforcement

A lint script at `scripts/lint/check-commit-hygiene.sh` enforces the rules above. It is wired into the `Commit Hygiene` GitHub Actions workflow (`.github/workflows/commit-hygiene.yml`), which runs on every pull request targeting `main` and blocks merge on failure. The lint also distinguishes pipe-authored commits (`chore(release):` / `chore(hotfix):`) — those are allowed to carry the marker because the pipe's atomic-push circuit breaker depends on it.

**Run the lint locally**:

```bash
# Against an inline message
scripts/lint/check-commit-hygiene.sh -m "feat: your subject"

# Against the commit message you are about to write
scripts/lint/check-commit-hygiene.sh -f .git/COMMIT_EDITMSG

# Against an open PR (requires gh CLI authenticated)
scripts/lint/check-commit-hygiene.sh -p 123
```

Exit codes: `0` clean, `1` forbidden substring found, `2` usage error.

**Exemption**: in the rare case that you *want* a commit to skip workflows (for example a pure-docs PR with no code to validate), add the trailer

```
X-Intentional-Skip-CI: true
```

on its own line in the commit body. The lint recognizes the trailer and lets the commit through. The trailer documents the intent explicitly, so the exemption is auditable in `git log`.

## Pull Request Process

1. Create a feature branch from `main`:

   ```bash
   git checkout -b feat/my-improvement
   ```

2. Make your changes following the code style guidelines above.

3. Run `make lint` and fix any shellcheck warnings.

4. Push your branch and open a pull request against `main`.

5. In your PR description, explain what the change does and why. Include relevant context and test steps.

6. One approving review is required before merging.

## Reporting Issues

Open a GitHub issue describing the problem. Include:
- The `.versioning.yml` config you are using (sanitized of any private URLs)
- The relevant pipeline output or error message
- The CI platform and environment (Bitbucket Pipelines, GitHub Actions, etc.)
