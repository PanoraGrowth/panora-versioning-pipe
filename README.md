# panora-versioning-pipe

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Registry: ECR Public](https://img.shields.io/badge/Registry-ECR%20Public-orange.svg)](https://gallery.ecr.aws/panoragrowth/versioning-pipe)

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

Add this step to your `bitbucket-pipelines.yml`:

```yaml
pipelines:
  pull-requests:
    '**':
      - step:
          name: Versioning (PR)
          image: public.ecr.aws/panoragrowth/versioning-pipe:latest
          variables:
            VERSIONING_PR_ID: $BITBUCKET_PR_ID
            VERSIONING_BRANCH: $BITBUCKET_BRANCH
            VERSIONING_TARGET_BRANCH: $BITBUCKET_PR_DESTINATION_BRANCH
            VERSIONING_COMMIT: $BITBUCKET_COMMIT
          script:
            - /pipe/pipe.sh

  branches:
    development:
      - step:
          name: Versioning (Tag)
          image: public.ecr.aws/panoragrowth/versioning-pipe:latest
          variables:
            VERSIONING_BRANCH: $BITBUCKET_BRANCH
            VERSIONING_COMMIT: $BITBUCKET_COMMIT
          script:
            - /pipe/pipe.sh
```

Place a `.versioning.yml` in your repository root. If the file doesn't exist, all defaults apply.

See [`examples/bitbucket-pipelines.yml`](examples/bitbucket-pipelines.yml) for a full example with optional variables.

## Installation

Pull the image from Amazon ECR Public:

```bash
docker pull public.ecr.aws/panoragrowth/versioning-pipe:latest
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

Set these four generic variables in your pipeline — map them from your CI platform's native variables:

| Variable | Description | Bitbucket | GitHub Actions |
|----------|-------------|-----------|----------------|
| `VERSIONING_PR_ID` | PR identifier — presence triggers the PR pipeline | `$BITBUCKET_PR_ID` | `${{ github.event.pull_request.number }}` |
| `VERSIONING_BRANCH` | Current / source branch name | `$BITBUCKET_BRANCH` | `${{ github.head_ref }}` (PR) or `${{ github.ref_name }}` (push) |
| `VERSIONING_TARGET_BRANCH` | PR target/destination branch | `$BITBUCKET_PR_DESTINATION_BRANCH` | `${{ github.base_ref }}` |
| `VERSIONING_COMMIT` | Current commit SHA | `$BITBUCKET_COMMIT` | `${{ github.sha }}` |

Optional variables you can set in your pipeline:

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

The default version format is:

```
MAJOR.MINOR.TIMESTAMP
```

Examples:
```
1.3.20240115143022        # major=1, minor=3, timestamp=2024-01-15 14:30:22 UTC
1.3.20240115143022-2      # collision suffix — second tag created in the same second
```

### Bump rules

| Commit type | Effect |
|-------------|--------|
| `major` | Increments Major, resets Minor to 0 |
| `minor` | Increments Minor |
| Any other type (`feat`, `fix`, `docs`, …) | Timestamp update only (Major and Minor unchanged) |

When `version.components.period.enabled: true`, the format becomes `PERIOD.MAJOR.MINOR.TIMESTAMP`.

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

Map GitHub's native variables to the pipe's generic `VERSIONING_*` vars:

```yaml
# .github/workflows/versioning.yml
jobs:
  version:
    runs-on: ubuntu-latest
    container:
      image: public.ecr.aws/panoragrowth/versioning-pipe:latest
    env:
      VERSIONING_PR_ID: ${{ github.event.pull_request.number }}
      VERSIONING_BRANCH: ${{ github.head_ref }}
      VERSIONING_TARGET_BRANCH: ${{ github.base_ref }}
      VERSIONING_COMMIT: ${{ github.sha }}
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - run: /pipe/pipe.sh
```

See [`examples/github-actions.yml`](examples/github-actions.yml) for a complete example with PR and branch pipeline jobs.

## Monorepo Support

For monorepos, enable `changelog.per_folder` and define `version_file.groups`:

**Per-folder changelogs** generate a `CHANGELOG.md` inside each matched subfolder. The commit scope (`feat(service-api): …`) is used to route entries to the right folder.

**Version file groups** let you define which version files to update when specific paths change. Each group has `trigger_paths` (glob patterns) and `files` (files to update). When a changed file matches a group's trigger paths, only that group's files are updated — unless `update_all: true` is set on the group.

See [`examples/.versioning-monorepo.yml`](examples/.versioning-monorepo.yml) for a complete configuration.

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
| [`.versioning-minimal.yml`](examples/.versioning-minimal.yml) | Bare minimum config — zero-config works |
| [`.versioning-ticket.yml`](examples/.versioning-ticket.yml) | Ticket format with Jira integration |
| [`.versioning-conventional.yml`](examples/.versioning-conventional.yml) | Conventional commits with emojis |
| [`.versioning-monorepo.yml`](examples/.versioning-monorepo.yml) | Monorepo with per-folder changelogs and grouped version files |
| [`bitbucket-pipelines.yml`](examples/bitbucket-pipelines.yml) | Full Bitbucket Pipelines example |
| [`github-actions.yml`](examples/github-actions.yml) | GitHub Actions workflow with env var mapping |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, code style, and the PR process.

## License

MIT — see [LICENSE](LICENSE).

Maintained by [Panora Growth](https://panoragrowth.com) — [oss@panoragrowth.com](mailto:oss@panoragrowth.com)
