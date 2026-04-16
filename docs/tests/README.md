# Test Coverage

Unit tests and integration tests validated before every release.

**As of ticket 050 (branches redesign)**: 363 unit tests (bats-core) and 13 end-to-end integration scenarios. Integration scenarios run against both GitHub and Bitbucket using a shared `test-scenarios.yml`. The `config_override` mechanism deep-merges deltas on top of the test repo's `.versioning.yml` (not a full replacement), so scenarios only specify keys they actually change.

---

## What we test

### Configuration System

- Default values load correctly when no `.versioning.yml` exists
- Project overrides merge on top of defaults
- All config keys: commit format, tickets, version components, separators, tag prefix, changelog options, branch names, validation rules
- `commit_type_overrides`: patch existing types, change bump levels, add new types
- Per-folder changelog config: folders list, scope matching (suffix/exact), fallback behavior, folder pattern

### Version Calculation

- Tag pattern generation for all component combinations (epoch, major, minor, patch, timestamp)
- Version string building from components, including the opt-in PATCH component
- Tag parsing and component extraction for v0.5.9 and v0.5.9.1 forms
- Timestamp-based tag handling
- v-prefix support
- Hotfix PATCH bump routing (scenario-driven, separate from last-commit-wins)
- PATCH reset on major/minor bumps, backward-compat fallback when patch is disabled

### Commit Validation

- Conventional commit patterns (`feat(scope): message`)
- Ticket-based patterns (`AM-1234 - feat: message`)
- Bump detection patterns (which commit types trigger major vs minor bumps)
- Ignore patterns (merge commits, reverts, release commits)
- Pattern matching against real commit strings

### Scenario Detection

- Feature → development = development release
- Feature → production (direct-to-main) = development release
- Development → pre-production = promotion (no action)
- Pre-production → production = promotion (no action)
- Hotfix → pre-production = hotfix changelog
- Hotfix → production = hotfix changelog
- Unknown target branch = no action
- Custom branch names (dev, staging, master, emergency/)
- **Branch context** (post-merge, no PR target): pure-git hotfix detection via commit subject glob patterns (`hotfix:*`, `hotfix(*`, `[Hh]otfix/*`) — platform-agnostic, no API calls

### Platform Detection

- Bitbucket: maps `BITBUCKET_*` environment variables to internal `VERSIONING_*` vars
- GitHub Actions: maps `GITHUB_*` vars for both PR and push events
- Generic CI: uses `VERSIONING_*` directly
- Priority: explicit `VERSIONING_*` overrides platform-specific vars
- Error handling: no platform detected = clean exit with error

### Per-Folder Changelog Routing

- Scoped commits route to correct subfolder CHANGELOG
- Suffix matching (`cluster-ecs` → `001-cluster-ecs/`)
- Exact matching (`api` → `api/`)
- Unscoped commits fall back to root CHANGELOG
- Subfolder discovery with folder patterns
- `find_folder_by_file_path()` — file-path fallback routing: single-folder match, no match, ambiguous (multi-folder), nested files, root-only files, mixed root+folder files

### Version File Groups (Monorepo)

- `matches_glob()` — glob-to-regex conversion: exact match, wildcards (`*`, `**`), dot escaping, cross-directory boundary checks, empty patterns
- Group config helpers: `has_version_file_groups`, `get_version_file_groups_count`, `get_version_file_group_trigger_paths`, `is_version_file_group_update_all`
- `unmatched_files_behavior` modes: `update_all` (default), `update_none`, `error`

### End-to-End (Integration)

These tests run against real repositories, creating actual PRs, merging, and verifying results:

- **feat commit → minor version bump** (`feat-minor-bump`): PR passes validation, merge creates new tag with correct version
- **fix commit → patch version bump** (`fix-patch-bump`): same flow, patch bump
- **chore commit → no version bump**: maintenance commits produce no tag (bump: none)
- **Scoped commit → per-folder CHANGELOG**: `feat(backend):` writes to `backend/CHANGELOG.md`
- **Scoped commit → different folder**: `fix(frontend):` writes to `frontend/CHANGELOG.md`
- **Unscoped commit → root CHANGELOG**: commits without scope go to root
- **Multi-commit PR → last commit wins**: PR with fix + feat (feat last) = minor bump under last-commit-only semantics; uses merge method (not squash) to preserve individual commits
- **Invalid commit format → PR validation fails**: non-conventional commit is rejected
- **Hotfix from production branch → PR check only**: validates the `hotfix` commit type through PR validation without merging (no tag created)
- **Hotfix to main with PATCH bump → full end-to-end**: merges a `hotfix:` commit squash-style from a `hotfix/auto-*` branch, verifies tag ends in `.1` and CHANGELOG header carries `(Hotfix)` marker
- **Hotfix with scope → PATCH bump**: `hotfix(security):` commit via squash merge validates the `hotfix(*` glob pattern produces patch bump and `(Hotfix)` marker
- **Hotfix uppercase branch prefix → PATCH bump**: `Hotfix/` branch prefix with PR title `Hotfix/description` validates the `[Hh]otfix/*` glob pattern — covers the real-world case where GitHub auto-generates the PR title from the branch name
- **Hotfix custom hotfix_targets → PR check**: validates PR check passes for a `hotfix/` branch when `config_override` sets a custom `branches.hotfix_targets` list — confirms new branch model routes correctly (PR-only, no merge)

---

## Platforms

- **GitHub Actions** — unit tests + integration tests (13 scenarios)
- **Bitbucket Pipelines** — unit tests + integration tests (13 scenarios, same `test-scenarios.yml`)

### Bitbucket integration notes

- Uses `BitbucketClient` (REST API v2.0 with Bearer token auth via `BB_TOKEN`)
- Squash merge requires explicit commit message — Bitbucket defaults to "Merged in branch (pull request #N)" which loses the conventional commit subject
- Tags sorted by `-target.date` (not name) for correct semver ordering
