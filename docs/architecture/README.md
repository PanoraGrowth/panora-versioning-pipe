# Architecture

**Last updated:** 2026-04-13 (floating version tags, ticket 032)

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
        ├── detect-scenario.sh        → routes hotfix vs development_release
        ├── calculate-version.sh      → determine next version (PATCH for hotfixes)
        ├── write-version-file.sh     → update version in project files
        ├── generate-changelog-per-folder.sh  → per-folder CHANGELOGs (monorepo)
        ├── generate-changelog-last-commit.sh → root CHANGELOG (+ "(Hotfix)" marker)
        ├── update-changelog.sh       → commit CHANGELOG (no push in branch context)
        └── atomic push: CHANGELOG commit + git tag (single push, CI-skip marker)
```

The PR pipeline only validates. The branch pipeline does all the work: scenario detection, version calculation, CHANGELOG generation, and tag creation.

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
[v]PERIOD.MAJOR.MINOR[.PATCH][.TIMESTAMP][-SUFFIX]
```

| Component | Bump trigger | Default |
|-----------|-------------|---------|
| v prefix | `version.tag_prefix_v` | off |
| Period | Manual / config change | off |
| Major | Commit types with `bump: "major"` (defaults: `major`, `breaking`, `feat`, `feature`) | on |
| Minor | Commit types with `bump: "minor"` (defaults: `minor`, `fix`, `hotfix`, `security`, `refactor`, `perf`, `docs`, `test`, `chore`, `build`, `ci`, `revert`, `style`) | on |
| Patch | Scenario-driven: `hotfix` scenario (from commit subject convention) bumps PATCH regardless of commit type (see "Hotfix flow") | on (v0.6.3+) |
| Timestamp | Auto-generated when no bump match | on |

Only the LAST commit in a PR determines the version bump. Commit types with `bump: "none"` skip tag creation entirely. Use `commit_type_overrides` to retune individual types without redefining the whole list (the pipe itself sets `docs: { bump: none }` in `.versioning.yml`).

### Bump calculation semantics

The pipe uses **last-commit-wins** semantics: only the most recent commit in the range drives the bump. Older commits in the range are invisible to the bump calculator. This is **intentional** and differs from semantic-release, release-please, and standard-version, which use **highest-bump-wins**.

- **Squash merge** (recommended): there is only one commit in the range, so last-wins and highest-wins are identical. No surprise.
- **Merge commit / rebase-and-merge**: commits `[feat: big, fix: small]` in that chronological order produce a **minor** bump from `fix:`, silently losing the `feat:`. Consumers using merge commits must either keep the highest-impact commit last, or switch to squash merge.

**Recommendation for consumers:** configure the watched branch to use **squash merge**. The rule lives at `scripts/versioning/calculate-version.sh:100-107` and is locked by the integration scenario `multi-commit-last-wins` in `tests/integration/test-scenarios.yml` (introduced in PR #38).

---

## Hotfix flow

The pipe supports hotfixes via a single unified scenario and a default-on PATCH version component (as of v0.6.3). Hotfixes are an explicit out-of-band release path: they bump the PATCH component (not MINOR), carry a `(Hotfix)` marker in the CHANGELOG header, and produce distinct tags like `v0.5.9.1` / `v0.5.9.2`. Each hotfix release is a stand-alone Docker image tag, so rollback is a plain `docker pull ghcr.io/.../panora-versioning-pipe:v0.5.9`.

### Detection

`scripts/detection/detect-scenario.sh` runs in two contexts:

| Context | Signal | Detection strategy |
|---------|--------|--------------------|
| PR | `VERSIONING_TARGET_BRANCH` set | Dispatches on source/target branch names — `hotfix/*` → main/pre-production becomes scenario `hotfix`. Heuristic uses `hotfix.keyword` as branch prefix. |
| Branch (post-merge) | No `VERSIONING_TARGET_BRANCH` | **Pure git, platform-agnostic**. Primary: merge-commit subject starts with `{keyword}:` or `{keyword}(`, where keyword comes from `hotfix.keyword` (default `"hotfix"`). Secondary: for traditional 3-way merge commits (HEAD has 2+ parents), the second parent's subject is also inspected — covers the merge-commit merge style where HEAD is "Merge pull request #N from ...". No API calls, no env vars, no `gh`/`bb` CLI. |

### Bump rules

| Scenario | `patch.enabled` | Bump | Tag | CHANGELOG | `(Hotfix)` marker |
|---|---|---|---|---|---|
| `development_release` | any | last-commit-wins (major/minor/none) | yes | yes | no |
| `hotfix` | `true` (default) | patch (increments by 1) | yes | yes | yes |
| `hotfix` | `false` (opt-out) | **no bump** | **no tag** | **no changelog** | n/a |

When a hotfix is detected but the consumer has opted out of patch (`patch.enabled: false`), the pipe emits a 3-line INFO log:

```
INFO: Hotfix commit detected ("hotfix: fix button") but version.components.patch.enabled is false.
INFO: Skipping tag creation (consumer opted out of patch component).
INFO: To enable hotfix tags, set version.components.patch.enabled: true in your .versioning.yml.
```

### Tag semantics (with `tag_prefix_v: true`)

- `v0.5.9` — patch=0, component omitted (backward-compat rendering)
- `v0.5.9.1` — first hotfix on top of `v0.5.9`
- `v0.5.9.2` — second hotfix on top of `v0.5.9.1`
- `v0.5.10` — next minor release; patch resets to 0 and is omitted again

### CHANGELOG marker

Hotfix releases render with a `(Hotfix)` suffix in the version header so release notes and commit digests are instantly distinguishable from standard releases:

```markdown
## v0.5.9.1 (Hotfix) - 2026-04-12

- hotfix: patch critical auth bypass
  - _oncall-engineer_
```

Both the root CHANGELOG (`generate-changelog-last-commit.sh`) and per-folder CHANGELOGs (`generate-changelog-per-folder.sh`) inject the marker consistently. Dev releases render unchanged.

### Configuration

```yaml
version:
  components:
    patch:
      enabled: true    # default on (v0.6.3+). Set to false to opt out.
      initial: 0

hotfix:
  keyword: "hotfix"    # default. Customize with any single-word keyword.
```

To opt out of the hotfix flow entirely, set `patch.enabled: false`. Hotfix commits then become a no-op with an INFO log (see the bump rules table above).

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
  mode: "last_commit"          # "last_commit" (default) or "full"
  per_folder:
    enabled: true
    folders:
      - "backend"
      - "frontend"
    scope_matching: "exact"    # "exact" or "suffix"
    fallback: "file_path"      # "root" (default) or "file_path"
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

The pipe ships with three workflows in `.github/workflows/`:

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `pr-versioning.yml` | `pull_request: [main]` | Validates commits and generates the CHANGELOG preview |
| `tag-on-merge.yml` | `push: [main]` | Runs the branch pipeline, creates the version tag |
| `publish.yml` | `workflow_run: [Main - Create Version Tag] / workflow_dispatch` | Builds the Docker image and pushes to GHCR + ECR Public |
| `run-unit-tests.yml` | `pull_request` on core paths | Runs the bats unit-test suite |

`tag-on-merge.yml` uses a GitHub App token (`CI_APP_ID` + `CI_APP_PRIVATE_KEY`) to push past branch protection and to re-trigger downstream workflows (the default `GITHUB_TOKEN` cannot do either).

The pipe auto-detects GitHub Actions and maps `GITHUB_*` variables to `VERSIONING_*` internally (see `pipe.sh:39-54`).

The branch pipeline's CHANGELOG commit uses the CI-skip marker to prevent re-triggering workflows. Tag + CHANGELOG are pushed atomically in a single `git push`.

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
| `/tmp/scenario.env` | Pipeline scenario (`development_release`, `hotfix`, `promotion_*`, `unknown`). Written by `detect-scenario.sh` before `calculate-version.sh` runs so the hotfix routing can drive the PATCH bump. |
| `/tmp/next_version.txt` | Calculated next version tag |
| `/tmp/bump_type.txt` | Bump type (`major`, `minor`, `patch`, `timestamp_only`) |
| `/tmp/latest_tag.txt` | Latest matching version tag |
| `/tmp/routed_commits.txt` | Commits routed to per-folder CHANGELOGs |
| `/tmp/per_folder_changelogs.txt` | Per-folder CHANGELOG paths for staging |
| `/tmp/version_files_modified.txt` | Modified version file paths for staging |
| `/tmp/changelog_committed.flag` | Signals CHANGELOG was committed, push pending |

---

## Docker image

```
Base: Alpine 3.19
Tools: bash, git, curl, jq, yq v4.35.1
Registries: ghcr.io/panoragrowth/panora-versioning-pipe
            public.ecr.aws/k5n8p2t3/panora-versioning-pipe
```

### Release tag strategy

Each release publishes three tags. Push order within each registry is always specific → minor series → major series, so a consumer pulling a floating tag during a rollout gets either the previous or the new image, never a torn state.

| Tag | Example | Mutability | Updated by hotfixes? |
|-----|---------|------------|----------------------|
| Specific | `:v0.9.1` | Immutable after publish | No |
| Minor series | `:v0.9` | Mutable (overwritten each 0.9.x release) | Yes |
| Major series | `:v0` | Mutable (overwritten each 0.x release) | Yes |

`:latest` is **not published** by policy. Floating tags are the supported ergonomics alternative — consumers choose their risk tolerance. See [adoption-guide.md](../adoption-guide.md#step-6--version-pinning-strategy) for guidance.

---

## Known limitations

1. **Last commit only for bumps**: only the last commit determines the version bump type. `changelog.mode: "full"` shows all commits in the CHANGELOG, but the bump is still from the last commit only. See "Bump calculation semantics" above for the rationale and the squash-merge recommendation.

2. **config_get_array and spaces**: array values with spaces in config (like regex patterns) will be split incorrectly. Avoid spaces in `ignore_patterns`.

3. **Tag format migration**: changing version format config (period, timestamp, v-prefix) causes old tags to be ignored. The pipe starts from initial values if no tags match the current pattern.

4. **Orphaned hotfix generator (REMOVED in v0.6.3)**: `scripts/changelog/generate-hotfix-changelog.sh` and its test file `tests/unit/changelog/hotfix.bats` were deleted in PR #49 (ticket 031). The unified wire-up (ticket 024) already routed hotfix releases through `generate-changelog-last-commit.sh` with a `(Hotfix)` header marker — the old generator was dead code.
