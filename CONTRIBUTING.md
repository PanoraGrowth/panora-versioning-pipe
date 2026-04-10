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

The pipe expects Bitbucket-compatible environment variables. To test a PR pipeline scenario locally:

```bash
BITBUCKET_PR_ID=1 \
BITBUCKET_BRANCH=feature/my-branch \
BITBUCKET_PR_DESTINATION_BRANCH=development \
BITBUCKET_COMMIT=abc1234 \
make run
```

The `make run` target mounts your current directory as `/workspace` inside the container. Place a `.versioning.yml` in the directory you run from to test different configurations.

See `examples/` for ready-to-use config examples.

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
