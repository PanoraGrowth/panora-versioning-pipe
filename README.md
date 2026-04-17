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
    image: public.ecr.aws/k5n8p2t3/panora-versioning-pipe:v0
    script:
      - /pipe/pipe.sh
```

**GitHub Actions (with org-level variable):**

```yaml
jobs:
  versioning:
    runs-on: ubuntu-latest
    container:
      image: ghcr.io/panoragrowth/panora-versioning-pipe:${{ vars.VERSIONING_PIPE_TAG }}
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
          ref: ${{ github.head_ref }}
      - run: /pipe/pipe.sh
```

Set `VERSIONING_PIPE_TAG` as an **organization variable** (Settings → Secrets and variables → Actions → Variables) to control the pipe version for all repos from one place. Override at repo level to pin a specific version.

> **Why `container.image` + `run:` instead of `uses: docker://`?** GitHub Actions does not support `${{ vars.* }}` expressions in the `uses:` key — it is parsed statically before contexts are resolved ([discussion](https://github.com/orgs/community/discussions/27048)). The `container.image` field does support vars, and the pattern mirrors Bitbucket's `image:` + `script:` approach. The entrypoint `/pipe/pipe.sh` is a stable public contract covered by semver.

The pipe publishes three tag levels per release — pin the one that matches your risk tolerance:

| Tag | Example | Updates automatically |
|-----|---------|-----------------------|
| Specific | `:v0.9.1` | Never |
| Minor series | `:v0.9` | On every 0.9.x patch |
| Major series | `:v0` | On every 0.x release |

`:latest` is not published. See [Version pinning strategy](docs/adoption-guide.md#step-6--version-pinning-strategy) for guidance.

Place a `.versioning.yml` in your repository root. If the file doesn't exist, all defaults apply.

See [`examples/`](examples/) for full pipeline examples for both platforms.

> **Why does Bitbucket need `script: - /pipe/pipe.sh` while GitHub Actions doesn't?**
>
> Bitbucket Pipelines always overrides the Docker ENTRYPOINT with `--entrypoint /bin/sh` and requires a `script:` block in every step. This is a Bitbucket platform limitation — the container's ENTRYPOINT never runs automatically. In GitHub Actions, `uses: docker://` respects the ENTRYPOINT, so the pipe runs with zero configuration. In both cases, platform variables (`BITBUCKET_*`, `GITHUB_*`) are auto-detected inside the container — no manual mapping needed.

## Installation

Pull the image from Amazon ECR Public:

```bash
docker pull public.ecr.aws/k5n8p2t3/panora-versioning-pipe:v0
```

Or from GitHub Container Registry:

```bash
docker pull ghcr.io/panoragrowth/panora-versioning-pipe:v0
```

Replace `:v0` with a minor series (`:v0.9`) or a specific tag (`:v0.9.1`) for tighter pinning. `:latest` is not published.

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
| `CI_GITHUB_TOKEN` | _(none)_ | GitHub App installation token used for push back to a protected branch. Required by the `tag-on-merge` workflow when `main` is protected — see [GitHub App setup](#github-app-setup-required-for-protected-main). |
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
    epoch:
      enabled: false   # First component — manually bumped integer (e.g. 1 in 1.3.20240115)
      initial: 0
    major:
      enabled: true    # Second component — bumped by commit types with bump: "major"
      initial: 0
    patch:
      enabled: true    # Third component — bumped by commit types with bump: "minor" or "patch"
      initial: 0
    hotfix_counter:
      enabled: true    # 4th component used by the hotfix flow. When enabled (default
                       # from v0.6.3), hotfix commits bump HOTFIX_COUNTER.
                       # Rendered only when > 0 (v0.5.9 stays v0.5.9 until a hotfix
                       # lands, then becomes v0.5.9.1). Set to false to opt out —
                       # hotfix commits become a no-op with an INFO log. See "Hotfix
                       # flow" below.
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

The default commit type list is built-in and covers the most common types. You can override individual fields per type via `commit_type_overrides` (see [`examples/configs/versioning-conventional.yml`](examples/configs/versioning-conventional.yml)) or replace the whole list via `commit_types:` in your `.versioning.yml`.

| Type | Changelog group | Default bump |
|------|-----------------|--------------|
| `breaking` | Breaking Changes | `major` — increments Major, resets Minor |
| `feat` / `feature` | Features | `minor` — increments Minor |
| `fix` | Bug Fixes | `patch` |
| `hotfix` | Hotfixes | `patch` — AND the merge commit subject starts with `hotfix:` or `hotfix(`. With `patch.enabled: false`, hotfix commits become a no-op. See "Hotfix flow" below. |
| `security` | Security | `patch` |
| `revert` | Reverts | `patch` |
| `perf` | Performance | `patch` |
| `refactor` | Refactoring | `none` |
| `docs` | Documentation | `none` |
| `test` | Testing | `none` |
| `chore` | Chores | `none` |
| `build` | Build | `none` |
| `ci` | CI/CD | `none` |
| `style` | Style | `none` |

Set a type's `bump` to `"none"` to keep a commit type out of version bumps entirely (common choice for `docs`). When only the last commit determines the bump and that commit is bump `none`, no tag is created.

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

  mode: "last_commit"           # "last_commit" (default) or "full" (all commits since last tag)

  # Per-folder changelogs (monorepo mode — requires commits.format: "conventional")
  per_folder:
    enabled: false
    folders: []                 # Folders that get their own CHANGELOG, e.g. ["backend", "frontend"]
    folder_pattern: ""          # Regex to filter subfolders (suffix mode), e.g. "^[0-9]{3}-"
    scope_matching: "suffix"    # "suffix": scope matches folder suffix; "exact": scope = folder name
    fallback: "root"            # "root" or "file_path" — behavior when scope doesn't match
```

### validation

```yaml
validation:
  require_ticket_prefix: false   # Alias for tickets.required
  require_commit_types: true     # Enforce typed commits. Scope follows changelog.mode:
                                 #   "last_commit" → only the last commit must be typed
                                 #   "full"        → all commits must be typed
                                 # Set to false to disable type validation entirely.
  ignore_patterns:               # Commit messages matching these patterns are skipped
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
  keyword: "hotfix"  # Commit type keyword that triggers the hotfix flow.
                     # Detection is a strict prefix match on the merge commit
                     # subject: "{keyword}:" or "{keyword}(". Change this if your
                     # team uses a different convention (e.g. "urgent", "critical",
                     # "fixprod"). Platform-agnostic — works identically on
                     # GitHub, Bitbucket, GitLab, and any git host.
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
| With epoch enabled | `EPOCH.MAJOR.MINOR.TIMESTAMP` | `0.1.3.20240115143022` |
| Without timestamp | `EPOCH.MAJOR.MINOR` or `MAJOR.MINOR` | `0.1.0` / `1.3` |
| With v prefix | Prepend `v` to any of the above | `v0.1.0` / `v1.3.20240115143022` |
| With PATCH enabled (hotfix released) | `...MINOR.PATCH[.TIMESTAMP]` | `v0.5.9.1` |
| With PATCH enabled (no hotfix yet) | `...MINOR` — patch omitted while `= 0` | `v0.5.9` |

A collision suffix (e.g. `-2`) is appended automatically when two tags are created in the same second.

Enable the `v` prefix by setting `version.tag_prefix_v: true` in your `.versioning.yml`.

Toggle individual components on or off via `version.components.<component>.enabled`.

### Bump rules

Only the **last commit** in the PR determines the bump. Each commit type has a `bump` field (see the table above) and the pipe resolves the bump from that field:

| `bump` value | Effect |
|--------------|--------|
| `major` | Increments Major, resets Patch and HotfixCounter to 0 |
| `minor` | Increments Patch (3rd slot), resets HotfixCounter to 0 |
| `patch` | Increments Patch (3rd slot), resets HotfixCounter to 0 |
| `none` | No tag created (commit is still recorded in CHANGELOG) |
| _unset / not matched_ | Timestamp update only (other components unchanged) — requires `timestamp` component enabled |

With the defaults, `breaking` bumps major; `feat` / `feature` bump minor; `fix` / `hotfix` / `security` / `revert` / `perf` bump patch; and `refactor` / `docs` / `chore` / etc. produce no bump. Override individual types via `commit_type_overrides` — a common pattern is `docs: { bump: "none" }` to keep documentation PRs from triggering releases.

### Hotfix flow

The pipe detects a hotfix release by inspecting the merge commit subject. Detection is **platform-agnostic** (pure git, no APIs) and enabled by default as of v0.6.3:

- **Detection**: the merge commit subject on the tag branch must start with `{keyword}:` or `{keyword}(`, where `{keyword}` is configured via `hotfix.keyword` (default `"hotfix"`). For squash merges, this means the **PR title** must start with the keyword. For rebase merges, the last replayed commit on the branch carries the signal. For traditional "merge commit" style, the branch tip (merge commit's second parent) is also inspected automatically.
- **No platform APIs**: the pipe uses `git log -1 --format='%s' HEAD` and, for merge commits, the second parent subject. Works identically on GitHub Actions, Bitbucket Pipelines, GitLab CI, or any git host.
- **Tag output**: `v0.5.9` → `v0.5.9.1` → `v0.5.9.2`, resetting to 0 (and being omitted) at the next minor release.
- **CHANGELOG header**: the version section is suffixed with `(Hotfix)` — e.g. `## v0.5.9.1 (Hotfix) - 2026-04-12`.
- **Strict prefix matching**: `hotfixed: foo`, `pre-hotfix: foo`, `a hotfix: foo` do NOT match. Only `hotfix:` or `hotfix(` at the start of the subject matches.
- **Custom keyword**: set `hotfix.keyword: "urgent"` (or any other word) to use a team-specific convention.

To disable the hotfix flow entirely, set `version.components.hotfix_counter.enabled: false`. Hotfix commits will then be treated as a no-op: the pipe emits a 3-line INFO log explaining the opt-out and creates no tag.

Full walkthrough: [`docs/adoption-guide.md`](docs/adoption-guide.md#step-5--when-and-how-to-use-hotfixes). Architecture deep-dive: [`docs/architecture/README.md`](docs/architecture/README.md#hotfix-flow).

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

Two single-job workflows — one for PRs, one for tag-on-merge. The pipe auto-detects all required context (`GITHUB_EVENT_NAME`, `GITHUB_HEAD_REF`, `GITHUB_BASE_REF`, `GITHUB_REF_NAME`, `GITHUB_SHA`, `GITHUB_EVENT_PATH`) from the Actions environment, so no explicit `VERSIONING_*` env vars are needed in the workflow. Copy these straight into `.github/workflows/` — they are identical to what the pipe itself runs on this repo.

```yaml
# .github/workflows/pr-versioning.yml (PR trigger)
on:
  pull_request:
    branches: [main]

permissions:
  contents: write

jobs:
  versioning:
    runs-on: ubuntu-latest
    container:
      image: ghcr.io/panoragrowth/panora-versioning-pipe:${{ vars.VERSIONING_PIPE_TAG }}
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
          ref: ${{ github.head_ref }}   # required — do not drop

      - run: /pipe/pipe.sh
```

```yaml
# .github/workflows/tag-on-merge.yml (main-branch trigger)
on:
  push:
    branches: [main]

permissions:
  contents: write

jobs:
  versioning:
    runs-on: ubuntu-latest
    container:
      image: ghcr.io/panoragrowth/panora-versioning-pipe:${{ vars.VERSIONING_PIPE_TAG }}
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

      - run: /pipe/pipe.sh
        env:
          CI_GITHUB_TOKEN: ${{ steps.ci-token.outputs.token }}
```

> **Why keep `ref: ${{ github.head_ref }}` in the PR checkout?** GitHub's default PR checkout lands on the ephemeral merge commit, but the pipe pushes the CHANGELOG commit back to the feature branch via `git push origin HEAD:refs/heads/<branch>`. HEAD must be the real feature branch commit, not the merge preview.

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
| [`examples/configs/versioning-hotfix.yml`](examples/configs/versioning-hotfix.yml) | Hotfix flow with opt-in PATCH component — produces tags like `v1.2.3.1` |
| [`examples/bitbucket/bitbucket-pipelines.yml`](examples/bitbucket/bitbucket-pipelines.yml) | Full Bitbucket Pipelines example |
| [`examples/github-actions/pr-versioning.yml`](examples/github-actions/pr-versioning.yml) | PR trigger — validates commits and generates CHANGELOG preview |
| [`examples/github-actions/tag-on-merge.yml`](examples/github-actions/tag-on-merge.yml) | Main-branch trigger — creates version tag (requires GitHub App token — see [GitHub App setup](#github-app-setup-required-for-protected-main)) |

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

### Skipping the versioning run

`tag-on-merge.yml` does not use `paths-ignore` — every push to `main` is considered a release candidate. The pipe has its own internal short-circuits (bump `none`, no new commits since last tag, or a commit subject that matches `validation.ignore_patterns`) and the CHANGELOG commit it creates is tagged with the CI-skip marker to prevent re-triggering itself.

### Manual trigger

`publish.yml` also supports `workflow_dispatch` for manual Docker image builds when needed.

## Security

For the pipe's security model, GitHub App token rationale, `CI_APP_PRIVATE_KEY` rotation runbook, and consumer security invariants, see [`docs/security.md`](docs/security.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, code style, and the PR process.

## License

MIT — see [LICENSE](LICENSE).

Maintained by [Panora Growth](https://panoragrowth.com) — [oss@panoragrowth.com](mailto:oss@panoragrowth.com)
