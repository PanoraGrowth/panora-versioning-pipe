# panora-versioning-pipe

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Registry: ECR Public](https://img.shields.io/badge/Registry-ECR%20Public-orange.svg)](https://gallery.ecr.aws/panoragrowth/versioning-pipe)
[![Registry: GHCR](https://img.shields.io/badge/Registry-GHCR-blue.svg)](https://github.com/PanoraGrowth/panora-versioning-pipe/pkgs/container/panora-versioning-pipe)

Automated versioning, changelog generation, and version file updates for CI/CD pipelines.

Runs as a Docker container step in your pipeline. Supports Bitbucket Pipelines natively, and GitHub Actions with a simple environment variable mapping.

## Features

- Semantic versioning with configurable version components (Major, Minor, Timestamp)
- Automatic CHANGELOG.md generation from commit messages
- Commit format validation (ticket-prefix or conventional commits)
- Monorepo support with per-folder changelogs and grouped version file updates
- Version file updates across YAML, JSON, and regex-based files
- Microsoft Teams notifications on success or failure
- Fully configurable via a `.versioning.yml` file — all keys are optional
- No lock-in: works in any CI environment that can run Docker

## Quick Start

Platform variables are auto-detected — no manual mapping needed.

**Bitbucket Pipelines:**

```yaml
- step:
    name: Versioning
    image: public.ecr.aws/k5n8p2t3/panora-versioning-pipe:latest
    script:
      - /pipe/pipe.sh
```

**GitHub Actions:**

```yaml
- uses: docker://ghcr.io/panoragrowth/panora-versioning-pipe:latest
```

Place a `.versioning.yml` in your repository root. If the file doesn't exist, all defaults apply.

See [`examples/`](examples/) for full pipeline examples for both platforms.

> **Why does Bitbucket need `script: - /pipe/pipe.sh` while GitHub Actions doesn't?**
>
> Bitbucket Pipelines always overrides the Docker ENTRYPOINT with `--entrypoint /bin/sh` and requires a `script:` block in every step. This is a Bitbucket platform limitation — the container's ENTRYPOINT never runs automatically. In GitHub Actions, `uses: docker://` respects the ENTRYPOINT, so the pipe runs with zero configuration. In both cases, platform variables (`BITBUCKET_*`, `GITHUB_*`) are auto-detected inside the container — no manual mapping needed.

## Installation

Pull the image from Amazon ECR Public:

```bash
docker pull public.ecr.aws/k5n8p2t3/panora-versioning-pipe:latest
```

Or from GitHub Container Registry:

```bash
docker pull ghcr.io/panoragrowth/panora-versioning-pipe:latest
```

No installation is needed in your pipeline — the image is referenced directly as the step runner.

## How It Works

**PR pipeline** (triggered when `VERSIONING_PR_ID` is set):
1. Detects the pipeline scenario (development release, hotfix, promotion)
2. Validates commit format against the configured style
3. Calculates the next version based on the last commit type
4. Updates version files (if configured)
5. Generates and commits a CHANGELOG entry

**Branch pipeline** (triggered when `VERSIONING_PR_ID` is not set):
1. Reads commits since the last version tag
2. Creates an annotated version tag and pushes it to the repository

## Environment Variables

On Bitbucket Pipelines and GitHub Actions, these variables are **auto-detected** from the platform — you don't need to set them. For other CI systems, set them manually:

| Variable | Description | Auto-detected on |
|----------|-------------|------------------|
| `VERSIONING_PR_ID` | PR identifier — presence triggers the PR pipeline | Bitbucket, GitHub |
| `VERSIONING_BRANCH` | Current / source branch name | Bitbucket, GitHub |
| `VERSIONING_TARGET_BRANCH` | PR target/destination branch | Bitbucket, GitHub |
| `VERSIONING_COMMIT` | Current commit SHA | Bitbucket, GitHub |

Optional variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `GIT_USER_NAME` | `CI Pipeline` | Git author name for automated commits (changelog, version file) |
| `GIT_USER_EMAIL` | `ci@panora-versioning-pipe.noreply` | Git author email for automated commits |
| `TEAMS_WEBHOOK_URL` | _(none)_ | Microsoft Teams incoming webhook URL for notifications |
| `BITBUCKET_API_TOKEN` | _(none)_ | Bitbucket app password for build status reporting (adapter only) |

The following are only required if you use the optional Bitbucket build-status adapter or Teams webhook templates that reference them:

| Variable | Description |
|----------|-------------|
| `BITBUCKET_REPO_OWNER` | Repository owner |
| `BITBUCKET_REPO_SLUG` | Repository slug |
| `BITBUCKET_BUILD_NUMBER` | Pipeline build number |

## Configuration Reference

Create a `.versioning.yml` file in your repository root. All keys are optional — defaults are applied automatically from [`scripts/defaults.yml`](scripts/defaults.yml).

### commits

```yaml
commits:
  format: "ticket"   # "ticket" (PROJ-123 - type: msg) or "conventional" (type(scope): msg)
```

### tickets

```yaml
tickets:
  prefixes: []       # e.g. ["PROJ", "TEAM"] — ticket prefix(es) to enforce
  required: false    # If true, every commit must have a recognized ticket prefix
  url: ""            # e.g. "https://your-org.atlassian.net/browse" — enables ticket links in changelog
```

### version

```yaml
version:
  tag_prefix_v: false  # When true, tags are prefixed with "v" (e.g. v0.1.0 instead of 0.1.0)
  components:
    period:
      enabled: false   # First component — manually bumped integer (e.g. 1 in 1.3.20240115)
      initial: 0
    major:
      enabled: true    # Second component — bumped by "major" commit type
      initial: 0
    minor:
      enabled: true    # Third component — bumped by "minor" commit type
      initial: 0
    patch:
      enabled: false   # Fourth component (rarely used alongside timestamp)
      initial: 0
    timestamp:
      enabled: true    # Auto-generated timestamp appended to version
      format: "%Y%m%d%H%M%S"
      timezone: "UTC"

  separators:
    version: "."       # Separator between version components
    timestamp: "."     # Separator before the timestamp
    suffix: ""         # Optional suffix appended after the timestamp
```

### commit_types

The default commit type list is built-in and covers the most common types. You can override it in your `.versioning.yml`:

| Type | Changelog group | Version bump |
|------|-----------------|--------------|
| `major` | Breaking Changes | Increments Major, resets Minor |
| `minor` | Release | Increments Minor |
| `feat` / `feature` | Features | Timestamp update only |
| `fix` | Bug Fixes | Timestamp update only |
| `hotfix` | Hotfixes | Timestamp update only |
| `security` | Security | Timestamp update only |
| `refactor` | Refactoring | Timestamp update only |
| `perf` | Performance | Timestamp update only |
| `docs` | Documentation | Timestamp update only |
| `test` | Testing | Timestamp update only |
| `chore` | Chores | Timestamp update only |
| `build` | Build | Timestamp update only |
| `ci` | CI/CD | Timestamp update only |
| `revert` | Reverts | Timestamp update only |
| `style` | Style | Timestamp update only |

### changelog

```yaml
changelog:
  file: "CHANGELOG.md"          # Path to the changelog file
  title: "Changelog"            # Title written at the top of the file
  format: "minimal"             # Changelog entry format (minimal is the only supported value)
  use_emojis: false             # Prepend each commit type with its emoji
  include_commit_link: true     # Link each entry to the commit (requires commit_url)
  include_ticket_link: true     # Link each entry to its ticket (requires tickets.url)
  include_author: true          # Include the commit author name in each entry
  commit_url: ""                # e.g. "https://github.com/your-org/your-repo/commit"
  ticket_link_label: "View ticket"  # Label for ticket links in changelog entries

  # Per-folder changelogs (monorepo mode — requires commits.format: "conventional")
  per_folder:
    enabled: false
    root_folders: []            # Folders to scan for subfolders, e.g. ["projects", "services"]
    folder_pattern: ""          # Regex to filter subfolders, e.g. "^[0-9]{3}-"
    scope_matching: "suffix"    # "suffix": scope matches folder suffix; "exact": scope = folder name
```

### validation

```yaml
validation:
  require_ticket_prefix: false         # Alias for tickets.required
  require_type_in_last_commit: true    # The last commit before the PR must have a valid type
  allow_untyped_intermediate_commits: true  # Intermediate commits don't need a type
  ignore_patterns:                     # Commit messages matching these patterns are skipped
    - "^Merge"
    - "^Revert"
    - "^fixup!"
    - "^squash!"
    - "^chore\\(release\\)"
    - "^chore\\(hotfix\\)"
```

### hotfix

```yaml
hotfix:
  branch_prefix: "hotfix/"          # Branches starting with this are treated as hotfix branches
  validate_commits: true            # Validate commit format on hotfix branches
  update_changelog_on_main: true    # Add a hotfix entry to the main branch changelog
  update_changelog_on_preprod: true # Add a hotfix entry to the pre-production changelog
  changelog_header: "HOTFIX"        # Section header used in hotfix changelog entries
```

### branches

```yaml
branches:
  development: "development"      # Development branch name
  pre_production: "pre-production" # Pre-production branch name
  production: "main"              # Production branch name
  tag_on: "development"           # Branch where version tags are created ("development" or "main")
```

### version_file

```yaml
version_file:
  enabled: false
  type: "yaml"           # "yaml", "json", or "regex"
  file: "version.yaml"   # File to update (yaml/json types)
  key: "version"         # Key to update (yaml/json types)
  pattern: ""            # Regex pattern to match (regex type)
  replacement: ""        # Replacement string — use {{VERSION}} as placeholder (regex type)

  # Monorepo groups — when defined, only files in matched groups are updated
  groups: []
  # Each group:
  #   name: "service-name"          # Label for logging
  #   trigger_paths:                # Glob patterns — if any changed file matches, this group triggers
  #     - "projects/service/**"
  #   files:                        # Files to update when this group triggers
  #     - "projects/service/src/version.ts"
  #   update_all: false             # If true, all groups are updated when this group triggers

  # Fallback for changed files that don't match any trigger_paths
  # "update_all" (default) | "update_none" | "error"
  unmatched_files_behavior: "update_all"
```

### notifications

```yaml
notifications:
  teams:
    enabled: true       # Master switch for Teams notifications
    on_success: false   # Send a notification on pipeline success
    on_failure: true    # Send a notification on pipeline failure
```

Requires `TEAMS_WEBHOOK_URL` to be set as an environment variable or pipeline secret.

## Version Format

The format depends on which components are enabled via `version.components.*.enabled`:

| Mode | Format | Example |
|------|--------|---------|
| Default (major + minor + timestamp) | `MAJOR.MINOR.TIMESTAMP` | `1.3.20240115143022` |
| With period enabled | `PERIOD.MAJOR.MINOR.TIMESTAMP` | `0.1.3.20240115143022` |
| Without timestamp | `PERIOD.MAJOR.MINOR` or `MAJOR.MINOR` | `0.1.0` / `1.3` |
| With v prefix | Prepend `v` to any of the above | `v0.1.0` / `v1.3.20240115143022` |

A collision suffix (e.g. `-2`) is appended automatically when two tags are created in the same second.

Enable the `v` prefix by setting `version.tag_prefix_v: true` in your `.versioning.yml`.

Toggle individual components on or off via `version.components.<component>.enabled`.

### Bump rules

| Commit type | Effect |
|-------------|--------|
| `major` | Increments Major, resets Minor to 0 |
| `minor` | Increments Minor |
| Any other type (`feat`, `fix`, `docs`, …) | Timestamp update only (Major and Minor unchanged) |

## Commit Formats

### Ticket format (`commits.format: "ticket"`)

```
PROJ-123 - feat: add OAuth2 support
PROJ-456 - fix: correct rate limiting edge case
PROJ-789 - minor: release new features
PROJ-000 - major: breaking API change
```

The ticket prefix is optional unless `tickets.required: true`.

### Conventional commits (`commits.format: "conventional"`)

```
feat(auth): add OAuth2 support
fix(api): correct rate limiting
feat: add new dashboard
minor: release new features
major: breaking change in config schema
```

The scope (in parentheses) is optional. It is used for per-folder changelog grouping when `changelog.per_folder.enabled: true`.

## GitHub Actions

The recommended approach uses a reusable workflow called by separate PR and branch trigger workflows. Map GitHub's native variables to the pipe's generic `VERSIONING_*` vars using the `docker://` action syntax:

```yaml
# .github/workflows/run-versioning.yml (reusable workflow)
on:
  workflow_call:
    inputs:
      pr_id:
        type: string
        default: ""
      branch:
        type: string
        required: true
      target_branch:
        type: string
        default: ""
      commit:
        type: string
        required: true

jobs:
  versioning:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: docker://public.ecr.aws/k5n8p2t3/panora-versioning-pipe:latest
        # Alternative: docker://ghcr.io/panoragrowth/panora-versioning-pipe:latest
        env:
          VERSIONING_PR_ID: ${{ inputs.pr_id }}
          VERSIONING_BRANCH: ${{ inputs.branch }}
          VERSIONING_TARGET_BRANCH: ${{ inputs.target_branch }}
          VERSIONING_COMMIT: ${{ inputs.commit }}
```

```yaml
# .github/workflows/pr-versioning.yml (PR caller)
on:
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
  versioning:
    uses: ./.github/workflows/run-versioning.yml
    with:
      pr_id: ${{ github.event.pull_request.number }}
      branch: ${{ github.head_ref }}
      target_branch: ${{ github.base_ref }}
      commit: ${{ github.sha }}
```

```yaml
# .github/workflows/tag-on-merge.yml (single-job inline pattern)
on:
  push:
    branches: [main]

permissions:
  contents: write

jobs:
  versioning:
    runs-on: ubuntu-latest
    steps:
      - id: ci-token
        uses: actions/create-github-app-token@v1
        with:
          app-id: ${{ secrets.CI_APP_ID }}
          private-key: ${{ secrets.CI_APP_PRIVATE_KEY }}

      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
          ref: main
          token: ${{ steps.ci-token.outputs.token }}

      - uses: docker://public.ecr.aws/k5n8p2t3/panora-versioning-pipe:latest
        env:
          VERSIONING_BRANCH: main
          VERSIONING_COMMIT: ${{ github.sha }}
          CI_GITHUB_TOKEN: ${{ steps.ci-token.outputs.token }}
```

See [`examples/github-actions/`](examples/github-actions/) for ready-to-use versions of these files.

### GitHub App setup (required for protected main)

The `tag-on-merge.yml` workflow needs to push a CHANGELOG commit and a version tag back to `main`. The default `GITHUB_TOKEN` cannot do this when `main` is protected, and it cannot re-trigger downstream workflows from its own pushes. A short-lived GitHub App token solves both problems.

**Steps**:

1. Create a GitHub App in your organization (Settings → Developer settings → GitHub Apps → New GitHub App). Minimal permissions: **Repository → Contents: Read & write**, **Repository → Metadata: Read-only**. No webhook needed.
2. Generate a private key for the App and download the PEM file.
3. Install the App on the consumer repository (App settings → Install App).
4. Add two secrets to the consumer repo (Settings → Secrets and variables → Actions):
   - `CI_APP_ID` — the numeric App ID
   - `CI_APP_PRIVATE_KEY` — the full PEM contents
5. The example `tag-on-merge.yml` already wires these secrets via `actions/create-github-app-token@v1`:

```yaml
- id: ci-token
  uses: actions/create-github-app-token@v1
  with:
    app-id: ${{ secrets.CI_APP_ID }}
    private-key: ${{ secrets.CI_APP_PRIVATE_KEY }}
```

The generated token is masked in logs, scoped to the installation, and expires in ~1 hour. It is used inline — in the same job — as the `token:` for `actions/checkout` and as `CI_GITHUB_TOKEN` for the pipe container, so no token is ever passed between jobs.

> The PR pipeline (`pr-versioning.yml`) does NOT need the App token — the default `GITHUB_TOKEN` with `contents: write` is enough because it only validates commits and pushes CHANGELOG updates to the PR head branch.

## Monorepo Support

For monorepos, enable `changelog.per_folder` and define `version_file.groups`:

**Per-folder changelogs** generate a `CHANGELOG.md` inside each matched subfolder. The commit scope (`feat(service-api): …`) is used to route entries to the right folder.

**Version file groups** let you define which version files to update when specific paths change. Each group has `trigger_paths` (glob patterns) and `files` (files to update). When a changed file matches a group's trigger paths, only that group's files are updated — unless `update_all: true` is set on the group.

See [`examples/configs/versioning-monorepo.yml`](examples/configs/versioning-monorepo.yml) for a complete configuration.

## Local Development

```bash
make build    # Build the Docker image (IMAGE_NAME=panora-versioning-pipe, IMAGE_TAG=local)
make run      # Run the pipe with the current directory mounted as /workspace
make shell    # Open an interactive bash shell inside the container
make lint     # Run shellcheck on all scripts (requires: brew install shellcheck)
```

Override defaults:

```bash
make build IMAGE_TAG=v1.0.0
```

## Examples

The [`examples/`](examples/) directory contains ready-to-use files:

| File | Description |
|------|-------------|
| [`examples/configs/versioning-minimal.yml`](examples/configs/versioning-minimal.yml) | Bare minimum config — zero-config works |
| [`examples/configs/versioning-conventional.yml`](examples/configs/versioning-conventional.yml) | Conventional commits with emojis |
| [`examples/configs/versioning-ticket.yml`](examples/configs/versioning-ticket.yml) | Ticket format with Jira integration |
| [`examples/configs/versioning-monorepo.yml`](examples/configs/versioning-monorepo.yml) | Monorepo with per-folder changelogs and grouped version files |
| [`examples/bitbucket/bitbucket-pipelines.yml`](examples/bitbucket/bitbucket-pipelines.yml) | Full Bitbucket Pipelines example |
| [`examples/github-actions/run-versioning.yml`](examples/github-actions/run-versioning.yml) | Reusable workflow — core versioning logic |
| [`examples/github-actions/pr-versioning.yml`](examples/github-actions/pr-versioning.yml) | PR trigger caller |
| [`examples/github-actions/tag-on-merge.yml`](examples/github-actions/tag-on-merge.yml) | Branch/tag trigger caller (requires GitHub App token — see [GitHub App setup](#github-app-setup-required-for-protected-main)) |

## CI/CD Architecture (for contributors and self-hosting)

This repo uses its own pipe for self-versioning. Understanding the workflow chain is important if you fork or adapt this project.

### Workflow chain

```
PR opened/updated
    └── pr-versioning.yml → validates commits, generates CHANGELOG preview
            │
            ▼ (PR check must pass before merge is allowed)

PR merged to main
    └── tag-on-merge.yml → runs the pipe, creates a version tag (e.g. v0.3.0)
            │
            ▼ (workflow_run: waits for tag-on-merge to complete)

    └── publish.yml → builds Docker image, tags it with the version, pushes to GHCR + ECR Public
```

### Why `workflow_run` instead of triggering on tag push?

GitHub Actions does not trigger workflows from tags created by other workflows using `GITHUB_TOKEN` — this is an intentional limitation to prevent infinite loops. Instead of working around this with a Personal Access Token, the publish workflow uses `workflow_run` to chain after `tag-on-merge` completes. This keeps the workflows sequential (like Bitbucket Pipelines) without extra secrets.

### Path filtering

`tag-on-merge.yml` uses `paths-ignore` to skip documentation-only changes. Since `publish.yml` triggers via `workflow_run` (not on push), it inherits this filtering — if `tag-on-merge` doesn't run, `publish` doesn't run either.

### Manual trigger

`publish.yml` also supports `workflow_dispatch` for manual Docker image builds when needed.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, code style, and the PR process.

## License

MIT — see [LICENSE](LICENSE).

Maintained by [Panora Growth](https://panoragrowth.com) — [oss@panoragrowth.com](mailto:oss@panoragrowth.com)
