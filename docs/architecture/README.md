# Architecture

**Version:** v0.4.2
**Last updated:** 2026-04-08

---

## Overview

panora-versioning-pipe is a CI/CD versioning tool packaged as a Docker image. It automates version calculation, tag creation, and CHANGELOG generation for projects using conventional commits.

Supported platforms: **GitHub Actions** and **Bitbucket Pipelines**.

---

## How it works

```
PR opened/updated
  └── pipe.sh → pr-pipeline.sh → validate commit format

Merge to tag branch (main or development)
  └── pipe.sh → branch-pipeline.sh
        ├── calculate-version.sh      → determine next version
        ├── write-version-file.sh     → update version in project files
        ├── generate-changelog-per-folder.sh  → per-folder CHANGELOGs (monorepo)
        ├── generate-changelog-last-commit.sh → root CHANGELOG
        ├── update-changelog.sh       → commit CHANGELOG (no push in branch context)
        └── atomic push: CHANGELOG commit + git tag (single push, [skip ci])
```

The PR pipeline only validates. The branch pipeline does all the work: version calculation, CHANGELOG generation, and tag creation.

---

## Repository structure

```
panora-versioning-pipe/
├── pipe.sh                    # Entry point — platform detection + routing
├── Dockerfile                 # Alpine 3.19 + bash/git/curl/jq/yq
├── scripts/
│   ├── defaults.yml           # All default config values
│   ├── lib/
│   │   ├── common.sh          # Shared utilities (logging, state, git ops)
│   │   └── config-parser.sh   # Config loading, version helpers, folder routing
│   ├── setup/                 # Git identity + dependency installation
│   ├── detection/             # Pipeline scenario detection
│   ├── validation/            # Commit message format validation
│   ├── versioning/            # Version calculation + file updates
│   ├── changelog/             # CHANGELOG generation (root + per-folder)
│   ├── orchestration/         # Pipeline orchestrators (PR + branch)
│   └── reporting/             # Notifications (Teams webhook, Bitbucket status)
├── tests/                     # Test framework (unit + integration)
├── docs/                      # Feature documentation + test coverage
├── .github/workflows/         # GitHub Actions workflows
└── examples/                  # Example configs + CI setups
```

---

## Configuration

The pipe uses a deep-merge configuration system:

1. `scripts/defaults.yml` ships with ALL default values
2. `.versioning.yml` in your repo overrides only what you need

You only specify what you want to change. Everything else inherits defaults.

### Minimal config example

```yaml
commits:
  format: "conventional"

version:
  tag_prefix_v: true
  components:
    period:
      enabled: true
    timestamp:
      enabled: false

branches:
  tag_on: "main"
```

This produces tags like `v0.1.0`, `v0.2.0`, etc.

### Full config reference

See `scripts/defaults.yml` for all available options with descriptions.

---

## Version system

Versions are built from toggleable components:

```
[v]PERIOD.MAJOR.MINOR[.TIMESTAMP][-SUFFIX]
```

| Component | Bump trigger | Default |
|-----------|-------------|---------|
| v prefix | Config | off |
| Period | Config change | off |
| Major | Commit types: `feat`, `major`, `breaking`, `feature` | on |
| Minor | Commit types: `fix`, `chore`, `docs`, `refactor`, `test`, etc. | on |
| Timestamp | Auto-generated | on |

Only the LAST commit in a PR determines the version bump.

---

## CHANGELOG system

### Modes

| Mode | Config | Behavior |
|------|--------|----------|
| `last_commit` | `changelog.mode: "last_commit"` | Only the last commit appears in the CHANGELOG (default) |
| `full` | `changelog.mode: "full"` | All commits since the last tag appear |

### Per-folder CHANGELOGs (monorepo)

When enabled, commits are routed to folder-specific CHANGELOGs based on their scope. Routing is **exclusive** — each entry goes to either a subfolder CHANGELOG or the root, never both.

```yaml
changelog:
  per_folder:
    enabled: true
    folders:
      - "backend"
      - "frontend"
    scope_matching: "exact"
    fallback: "file_path"
```

**Routing flow:**

```
1. No scope → root CHANGELOG
2. Scope matches a configured folder → folder/CHANGELOG.md
3. Scope matches a subfolder within a configured folder → folder/scope/CHANGELOG.md
4. fallback: "file_path" → check modified files → route to parent folder
5. No match → root CHANGELOG
```

**Example:**

```
feat(backend): new API        → backend/CHANGELOG.md
feat(auth-service): add OAuth → backend/auth-service/CHANGELOG.md  (subfolder discovery)
feat(cloudfront): add CDN     → backend/CHANGELOG.md               (file_path fallback)
feat: general feature         → CHANGELOG.md                       (no scope → root)
```

See `docs/per-folder-changelog/README.md` for full documentation.

---

## Platform support

### GitHub Actions

```yaml
# PR validation + unit tests (only when core files change)
on:
  pull_request:
    branches: [main]
    paths: [scripts/**, pipe.sh, Dockerfile, tests/**, Makefile]

# Tag creation on merge
on:
  push:
    branches: [main]

# Release (triggered by tag-on-merge completion)
on:
  workflow_run:
    workflows: ["Main - Create Version Tag"]
    types: [completed]
```

The pipe auto-detects GitHub Actions and maps `GITHUB_*` variables to `VERSIONING_*`.

The branch pipeline's CHANGELOG commit uses `[skip ci]` to prevent re-triggering workflows. Tag + CHANGELOG are pushed atomically in a single `git push`.

### Bitbucket Pipelines

```yaml
pipelines:
  pull-requests:
    '**':
      - step:
          image: public.ecr.aws/k5n8p2t3/panora-versioning-pipe:latest
          script:
            - /pipe/pipe.sh
  branches:
    main:
      - step:
          image: public.ecr.aws/k5n8p2t3/panora-versioning-pipe:latest
          script:
            - /pipe/pipe.sh
```

Bitbucket overrides Docker ENTRYPOINT, so `/pipe/pipe.sh` must be called explicitly.

### Generic CI

Set these environment variables manually:

| Variable | Required | Description |
|----------|----------|-------------|
| `VERSIONING_BRANCH` | Yes (branch pipeline) | Current branch name |
| `VERSIONING_PR_ID` | Yes (PR pipeline) | Pull request ID |
| `VERSIONING_TARGET_BRANCH` | Yes (PR pipeline) | PR target branch |
| `VERSIONING_COMMIT` | Optional | Current commit SHA |

---

## Inter-script communication

Scripts communicate via temp files:

| File | Purpose |
|------|---------|
| `/tmp/scenario.env` | Pipeline scenario (development_release, hotfix, etc.) |
| `/tmp/next_version.txt` | Calculated next version tag |
| `/tmp/bump_type.txt` | Bump type (major, minor, timestamp_only) |
| `/tmp/latest_tag.txt` | Latest matching version tag |
| `/tmp/routed_commits.txt` | Commits routed to per-folder CHANGELOGs |
| `/tmp/per_folder_changelogs.txt` | Per-folder CHANGELOG paths for staging |

---

## Docker image

```
Base: Alpine 3.19
Tools: bash, git, curl, jq, yq v4.35.1
Registries: ghcr.io/panoragrowth/panora-versioning-pipe
            public.ecr.aws/k5n8p2t3/panora-versioning-pipe
Tags: :latest, :vX.Y.Z (version-specific)
```

---

## Known limitations

1. **Last commit only for bumps**: only the last commit determines the version bump type. `changelog.mode: "full"` shows all commits in the CHANGELOG, but the bump is still from the last commit only.

2. **Patch component not implemented**: `version.components.patch` exists in config but has no bump logic.

3. **config_get_array and spaces**: array values with spaces in config (like regex patterns) will be split incorrectly. Avoid spaces in `ignore_patterns`.

4. **Tag format migration**: changing version format config (period, timestamp, v-prefix) causes old tags to be ignored. The pipe starts from initial values if no tags match the current pattern.
