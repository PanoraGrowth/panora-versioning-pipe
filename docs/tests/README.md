# Test Coverage

Unit tests and integration tests validated before every release.

**As of ticket 024 (hotfix wire-up)**: 272 unit tests (bats-core) and 10 end-to-end integration scenarios. Integration scenarios run against both GitHub and Bitbucket except for the hotfix-to-main-with-patch-bump scenario, which is GitHub-only while the bitbucket harness catches up with `branch_prefix` / `pr_title` / `config_override` support.

---

## What we test

### Configuration System

- Default values load correctly when no `.versioning.yml` exists
- Project overrides merge on top of defaults
- All config keys: commit format, tickets, version components, separators, tag prefix, changelog options, branch names, validation rules
- `commit_type_overrides`: patch existing types, change bump levels, add new types
- Per-folder changelog config: folders list, scope matching (suffix/exact), fallback behavior, folder pattern

### Version Calculation

- Tag pattern generation for all component combinations (period, major, minor, patch, timestamp)
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
- **Branch context** (post-merge, no PR target): hotfix detection via commit-type convention (`hotfix:` / `hotfix(...)`) and GitHub API PR lookup fallback

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

### End-to-End (Integration)

These tests run against real repositories, creating actual PRs, merging, and verifying results:

- **feat commit → major version bump**: PR passes validation, merge creates new tag with correct version
- **fix commit → minor version bump**: same flow, minor bump
- **chore commit → minor version bump**: maintenance commits still bump
- **Scoped commit → per-folder CHANGELOG**: `feat(backend):` writes to `backend/CHANGELOG.md`
- **Scoped commit → different folder**: `fix(frontend):` writes to `frontend/CHANGELOG.md`
- **Unscoped commit → root CHANGELOG**: commits without scope go to root
- **Multi-commit PR → highest bump wins**: PR with fix + feat = major bump (feat wins)
- **Invalid commit format → PR validation fails**: non-conventional commit is rejected
- **Hotfix from production branch → PR check only**: validates the `hotfix` commit type through PR validation without merging (no tag created)
- **Hotfix to main with PATCH bump → full end-to-end**: opts into the PATCH component via `config_override`, merges a `hotfix:` commit squash-style from a `hotfix/auto-*` branch, and verifies the resulting tag ends in `.1` and the CHANGELOG section header carries the `(Hotfix)` marker (GitHub only at v0.5.10)

---

## Platforms

- **GitHub Actions** — unit tests + integration tests (10 scenarios)
- **Bitbucket Pipelines** — unit tests + integration tests (9 scenarios, same `test-scenarios.yml`; the hotfix wire-up scenario is `skip_bitbucket: true` pending harness parity)

### Bitbucket integration notes

- Uses `BitbucketClient` (REST API v2.0 with Bearer token auth via `BB_TOKEN`)
- Squash merge requires explicit commit message — Bitbucket defaults to "Merged in branch (pull request #N)" which loses the conventional commit subject
- Tags sorted by `-target.date` (not name) for correct semver ordering
