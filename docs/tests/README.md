# Test Coverage

Unit tests and integration tests validated before every release.

---

## What we test

### Configuration System

- Default values load correctly when no `.versioning.yml` exists
- Project overrides merge on top of defaults
- All config keys: commit format, tickets, version components, separators, tag prefix, changelog options, branch names, validation rules
- `commit_type_overrides`: patch existing types, change bump levels, add new types
- Per-folder changelog config: folders list, scope matching (suffix/exact), fallback behavior, folder pattern

### Version Calculation

- Tag pattern generation for all component combinations (period, major, minor, timestamp)
- Version string building from components
- Tag parsing and component extraction
- Timestamp-based tag handling
- v-prefix support

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

---

## Platforms

- **GitHub Actions** — unit tests + integration tests
- **Bitbucket Pipelines** — unit tests (integration tests coming soon)
