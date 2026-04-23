# Architecture

**Last updated:** 2026-04-21 (Go cutover, GO-12)

---

## Overview

panora-versioning-pipe is a CI/CD versioning tool packaged as a Docker image. It automates version calculation, tag creation, and CHANGELOG generation for projects using conventional commits.

Supported platforms: **GitHub Actions** and **Bitbucket Pipelines**.

The runtime is a single Go binary (`panora-versioning`). Bash, `jq`, `yq`, and `curl` were removed in GO-12; the image carries only `git` and `tzdata` on top of Alpine.

---

## How it works

```
PR opened/updated
  └── panora-versioning (default cmd)
        ├── preflight: configure-git → platform detect → config-parse
        └── pr-pipeline → detect-scenario → validate-commits

Merge to tag branch (main or development)
  └── panora-versioning (default cmd)
        ├── preflight: configure-git → platform detect → config-parse
        └── branch-pipeline
              ├── detect-scenario              → routes hotfix vs development_release
              ├── calc-version                 → next version (PATCH for hotfixes)
              ├── run-guardrails               → invariants enforced before side effects
              ├── write-version-file           → update version in project files
              ├── generate-changelog-per-folder → per-folder CHANGELOGs (monorepo)
              ├── generate-changelog-last-commit → root CHANGELOG (+ "(Hotfix)" marker)
              ├── update-changelog             → commit CHANGELOG (no push yet)
              └── atomic push: CHANGELOG commit + git tag (single push, CI-skip marker)
```

The PR pipeline only validates. The branch pipeline does all the work: scenario detection, version calculation, guardrails, CHANGELOG generation, and tag creation.

Each stage above is a subcommand of the same binary. The default command (no subcommand) replicates the old `pipe.sh` entry point: it runs preflight, then dispatches to `pr-pipeline` or `branch-pipeline` based on `VERSIONING_PR_ID` / `VERSIONING_BRANCH`. Subcommands can also be invoked directly for debugging or composition.

---

## Repository structure

```
panora-versioning-pipe/
├── cmd/panora-versioning/        # Go entry point (cobra root + subcommands)
│   ├── main.go                   # Root command — default run dispatches PR/branch
│   ├── pr_pipeline.go            # pr-pipeline subcommand
│   ├── branch_pipeline.go        # branch-pipeline subcommand
│   ├── configure_git.go          # configure-git (identity, remote auth, fetch)
│   ├── config_parse.go           # config-parse (deep merge → merged YAML)
│   ├── detect_scenario.go        # detect-scenario (hotfix vs development_release)
│   ├── calc_version.go           # calc-version
│   ├── run_guardrails.go         # run-guardrails (+ guardrails subcommand)
│   ├── write_version_file.go     # write-version-file
│   ├── generate_changelog_*.go   # per-folder and last-commit CHANGELOG generators
│   ├── update_changelog.go       # update-changelog (stage + commit)
│   ├── validate_commits.go       # validate-commits (PR pipeline)
│   ├── check_commit_hygiene.go   # check-commit-hygiene (extra PR check)
│   ├── check_release_readiness.go# check-release-readiness
│   ├── notify_teams.go           # Teams webhook notifier
│   └── bitbucket_build_status.go # Bitbucket build status reporter
├── internal/
│   ├── pipeline/                 # Orchestrator: preflight, PR/branch dispatch, platform detect + env mapping
│   ├── config/                   # YAML load, deep-merge, bundled-defaults path resolution
│   ├── versioning/               # Version calculation + bump strategy (last-commit-wins, highest-wins)
│   ├── detection/                # Scenario detection (PR branch dispatch + post-merge git heuristics)
│   ├── validation/               # Commit message format + hygiene checks
│   ├── guardrails/               # Runtime invariants (no_version_regression, etc.)
│   ├── changelog/                # CHANGELOG generation (root + per-folder) + update/commit
│   ├── versionfile/              # Version file patchers for project manifests
│   ├── gitops/                   # Git helpers (fetch, tag, push, merge-commit inspection)
│   ├── release/                  # Release readiness + tag push orchestration
│   ├── reporting/                # Teams webhook + Bitbucket build status payloads
│   └── util/                     # log, state (/tmp contract helpers), version metadata
├── config/defaults/
│   ├── defaults.yml              # All default config values (bundled into image)
│   └── commit-types.yml          # Default commit-type → bump mapping
├── Dockerfile                    # Multi-stage: golang:1.26-alpine → alpine:3.19 + git + tzdata
├── tests/                        # Unit (go test) + integration (pytest + gh CLI)
├── docs/                         # Feature documentation + architecture reference
├── .github/workflows/            # GitHub Actions workflows
└── examples/                     # Example configs + CI setups
```

The Docker image ships the Go binary at `/usr/local/bin/panora-versioning` and the bundled YAML defaults at `/etc/panora/defaults/`.

---

## Configuration

The pipe uses a deep-merge configuration system:

1. `config/defaults/defaults.yml` ships with ALL default values (bundled into the image at `/etc/panora/defaults/defaults.yml`)
2. `.versioning.yml` in your repo overrides only what you need

You only specify what you want to change. Everything else inherits defaults.

The runtime path for bundled defaults is `/etc/panora/defaults/`. For tests and local runs you can override it with the `PANORA_DEFAULTS_DIR` environment variable — `internal/config.ResolveBundledFile` checks the env override first, then the baked-in path, then two fallbacks next to the binary.

### Minimal config example

```yaml
commits:
  format: "conventional"

version:
  tag_prefix_v: true
  components:
    epoch:
      enabled: true
    timestamp:
      enabled: false

branches:
  tag_on: "main"
```

This produces tags like `v0.1.0`, `v0.2.0`, etc.

### Full config reference

See `config/defaults/defaults.yml` for all available options with descriptions.

---

## Version system

Versions are built from toggleable components:

```
[v]EPOCH.MAJOR.MINOR[.PATCH][.TIMESTAMP][-SUFFIX]
```

| Component | Bump trigger | Default |
|-----------|-------------|---------|
| v prefix | `version.tag_prefix_v` | off |
| Epoch | Manual / config change | off |
| Major | Commit types with `bump: "major"` (defaults: `breaking`) | on |
| Minor | Commit types with `bump: "minor"` (defaults: `feat`, `feature`) | on |
| Patch | Scenario-driven: `hotfix` scenario (from commit subject convention) bumps PATCH regardless of commit type (see "Hotfix flow"). Also: `fix`, `hotfix`, `security`, `revert`, `perf` | on (v0.6.3+) |
| None | Commit types that produce no version bump (defaults: `refactor`, `docs`, `test`, `chore`, `build`, `ci`, `style`) | — |
| Timestamp | Auto-generated when no bump match | on |

The commit that drives the bump is determined by `changelog.mode`. Commit types with `bump: "none"` skip tag creation entirely. Use `commit_type_overrides` to retune individual types without redefining the whole list (the pipe itself sets `docs: { bump: none }` in `.versioning.yml`).

### Bump calculation semantics

The bump strategy is coupled to `changelog.mode`:

| `changelog.mode` | Bump strategy | Behavior |
|---|---|---|
| `last_commit` (default) | last-commit-wins | Only the most recent commit in the range drives the bump. Backward-compatible. |
| `full` | highest-wins | All commits in the range are scanned. The highest-ranked bump wins: `major > minor > patch > timestamp_only`. |

The coupling is intentional: if you want all commits visible in the CHANGELOG (`mode: full`), you also want the strongest version signal from those same commits. There is no configuration to mix `last_commit` mode with highest-wins bump, nor the reverse — the two concepts are coherent by design.

**Squash merge** (recommended for `last_commit` mode): there is only one commit in the range, so last-wins and highest-wins produce identical results.

**Merge commit / rebase-and-merge with `last_commit` mode**: commits `[feat: big, fix: small]` in that chronological order produce a **patch** bump, silently losing the `feat:`. Use `mode: full` or squash merge to avoid this.

The implementation lives in `internal/versioning` and is locked by integration scenarios `multi-commit-last-wins` (sandbox-06) and `multi-commit-highest-wins` (sandbox-25) in `tests/integration/test-scenarios.yml`.

---

## Hotfix flow

The pipe supports hotfixes via a single unified scenario and a default-on PATCH version component (as of v0.6.3). Hotfixes are an explicit out-of-band release path: they bump the PATCH component (not MINOR), carry a `(Hotfix)` marker in the CHANGELOG header, and produce distinct tags like `v0.5.9.1` / `v0.5.9.2`. Each hotfix release is a stand-alone Docker image tag, so rollback is a plain `docker pull ghcr.io/.../panora-versioning-pipe:v0.5.9`.

### Detection

`internal/detection` runs in two contexts (invoked through the `detect-scenario` subcommand):

| Context | Signal | Detection strategy |
|---------|--------|--------------------|
| PR | `VERSIONING_TARGET_BRANCH` set | Dispatches on source/target branch names — target == `branches.tag_on` → `development_release`; target in `branches.hotfix_targets` + source starts with `hotfix.branch_prefix` → `hotfix`; target in `branches.hotfix_targets` + source == `tag_on` → `promotion_to_main`. Source-branch detection uses the explicit `hotfix.branch_prefix` config (default `"hotfix/"`). |
| Branch (post-merge) | No `VERSIONING_TARGET_BRANCH` | **Pure git, platform-agnostic**. Primary: merge-commit subject matches any pattern in `hotfix.keyword` (Go regex, defaults match `hotfix:`/`hotfix(scope):`/`Hotfix/branch`/`URGENT-PATCH`). Secondary: for traditional 3-way merge commits (HEAD has 2+ parents), the second parent's subject is inspected — covers the merge-commit style where HEAD is "Merge pull request #N from ...". No API calls, no env vars, no `gh`/`bb` CLI. |

### Bump rules

| Scenario | `hotfix_counter.enabled` | Bump | Tag | CHANGELOG | `(Hotfix)` marker |
|---|---|---|---|---|---|
| `development_release` | any | last-commit-wins or highest-wins (per `changelog.mode`) | yes | yes | no |
| `hotfix` | `true` (default) | hotfix_counter (increments by 1) | yes | yes | yes |
| `hotfix` | `false` (opt-out) | **no bump** | **no tag** | **no changelog** | n/a |

When a hotfix is detected but the consumer has opted out of hotfix_counter (`hotfix_counter.enabled: false`), the pipe emits a 3-line INFO log:

```
INFO: Hotfix commit detected ("hotfix: fix button") but version.components.hotfix_counter.enabled is false.
INFO: Skipping tag creation (consumer opted out of hotfix_counter component).
INFO: To enable hotfix tags, set version.components.hotfix_counter.enabled: true in your .versioning.yml.
```

### Tag semantics (with `tag_prefix_v: true`)

- `v0.5.9` — hotfix_counter=0, component omitted (backward-compat rendering)
- `v0.5.9.1` — first hotfix on top of `v0.5.9`
- `v0.5.9.2` — second hotfix on top of `v0.5.9.1`
- `v0.5.10` — next patch release; hotfix_counter resets to 0 and is omitted again

### CHANGELOG marker

Hotfix releases render with a `(Hotfix)` suffix in the version header so release notes and commit digests are instantly distinguishable from standard releases:

```markdown
## v0.5.9.1 (Hotfix) - 2026-04-12

- hotfix: patch critical auth bypass
  - _oncall-engineer_
```

Both the root CHANGELOG (`generate-changelog-last-commit` subcommand) and per-folder CHANGELOGs (`generate-changelog-per-folder` subcommand) inject the marker consistently. Dev releases render unchanged. Both are backed by `internal/changelog`.

### Configuration

```yaml
version:
  components:
    hotfix_counter:
      enabled: true    # default on (v0.6.3+). Set to false to opt out.
      initial: 0

hotfix:
  keyword: "hotfix"    # default. Customize with any single-word keyword.
```

To opt out of the hotfix flow entirely, set `hotfix_counter.enabled: false`. Hotfix commits then become a no-op with an INFO log (see the bump rules table above).

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
| `run-unit-tests.yml` | `pull_request` on core paths | Runs the Go unit-test suite |

`tag-on-merge.yml` uses a GitHub App token (`CI_APP_ID` + `CI_APP_PRIVATE_KEY`) to push past branch protection and to re-trigger downstream workflows (the default `GITHUB_TOKEN` cannot do either).

The pipe auto-detects GitHub Actions and maps `GITHUB_*` variables to `VERSIONING_*` internally. Platform detection and env mapping live in `internal/pipeline/platform.go` and are invoked during the default-command preflight.

The branch pipeline's CHANGELOG commit uses the CI-skip marker to prevent re-triggering workflows. Tag + CHANGELOG are pushed atomically in a single `git push`.

### Bitbucket Pipelines

```yaml
pipelines:
  pull-requests:
    '**':
      - step:
          image: public.ecr.aws/k5n8p2t3/panora-versioning-pipe:latest
  branches:
    main:
      - step:
          image: public.ecr.aws/k5n8p2t3/panora-versioning-pipe:latest
```

The container ENTRYPOINT is `/usr/local/bin/panora-versioning`. Bitbucket honors it directly — no explicit script call is required now that the bash entry point is gone. If you override the entry point or need a sub-behavior, invoke a subcommand explicitly (e.g. `- /usr/local/bin/panora-versioning branch-pipeline`).

### Generic CI

Set these environment variables manually:

| Variable | Required | Description |
|----------|----------|-------------|
| `VERSIONING_BRANCH` | Yes (branch pipeline) | Current branch name |
| `VERSIONING_PR_ID` | Yes (PR pipeline) | Pull request ID |
| `VERSIONING_TARGET_BRANCH` | Yes (PR pipeline) | PR target branch |
| `VERSIONING_COMMIT` | Optional | Current commit SHA |

---

## Inter-stage state

Although all logic lives in a single Go binary, each pipeline stage is executed as a subcommand in its own process (the orchestrator uses a `SelfExecRunner` so each stage runs with a clean environment and a predictable exit code). Stages therefore persist a small amount of state through `/tmp` files — the same contract the integration tests rely on:

| File | Purpose | Producer |
|------|---------|----------|
| `/tmp/.versioning-merged.yml` | Deep-merged config (defaults + `.versioning.yml`) consumed by every downstream stage | `config-parse` |
| `/tmp/scenario.env` | Pipeline scenario (`development_release`, `hotfix`, `promotion_*`, `unknown`). Written before `calc-version` so hotfix routing can drive the PATCH bump. | `detect-scenario` |
| `/tmp/next_version.txt` | Calculated next version tag | `calc-version` |
| `/tmp/bump_type.txt` | Bump type (`major`, `minor`, `patch`, `timestamp_only`) | `calc-version` |
| `/tmp/latest_tag.txt` | Latest matching version tag | `calc-version` |
| `/tmp/routed_commits.txt` | Commits routed to per-folder CHANGELOGs | `generate-changelog-per-folder` |
| `/tmp/per_folder_changelogs.txt` | Per-folder CHANGELOG paths for staging | `generate-changelog-per-folder` |
| `/tmp/version_files_modified.txt` | Modified version file paths for staging | `write-version-file` |
| `/tmp/changelog_committed.flag` | Signals CHANGELOG was committed, push pending | `update-changelog` |

Helpers for reading/writing this contract live in `internal/util/state`. Paths are passed in — never hardcoded inside handlers — so tests can redirect them.

---

## Docker image

```
Base:     Alpine 3.19 (runtime stage)
Builder:  golang:1.26-alpine (compiles static binary, CGO disabled)
Runtime:  git, tzdata (pure Go binary — no bash, no jq, no yq, no curl)
Binary:   /usr/local/bin/panora-versioning
Defaults: /etc/panora/defaults/{defaults.yml, commit-types.yml}
User:     pipe (UID 1001, non-root)
TZ:       UTC (required by the tag timestamp formatter)
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

## Migration notes

### v0.11+ — `major` and `minor` commit types removed

The `major` and `minor` commit types were removed from `config/defaults/defaults.yml` in this version. Consumers using these types will experience a silent behavior change:

- `major:` commits no longer trigger a major bump — they are unrecognized and fall through to timestamp-only behavior.
- `minor:` commits no longer trigger a minor bump — same fallback.

**Correct mapping going forward:**

| Intent | Use instead |
|--------|-------------|
| Major version bump (breaking change) | `breaking:` or `breaking(scope):` — bump: `major` |
| Minor version bump (new feature) | `feat:` or `feature:` — bump: `minor` |

If you relied on `major:` or `minor:` as commit types in your history or tooling, add them back via `commit_type_overrides` in your `.versioning.yml`:

```yaml
commit_type_overrides:
  - type: "major"
    bump: "major"
    changelog_section: "Breaking Changes"
  - type: "minor"
    bump: "minor"
    changelog_section: "Release"
```

### v1.0+ — Go cutover (GO-12)

The entire bash runtime (`pipe.sh`, `scripts/*.sh`, `scripts/lib/*.sh`) was removed. The container image no longer ships `bash`, `jq`, `yq`, `curl`, `gettext`, or `coreutils`. Only `git` and `tzdata` remain on top of Alpine. All behavior is driven by the Go binary at `/usr/local/bin/panora-versioning`.

Consumer impact:

- **No config change required.** `.versioning.yml` schema is unchanged.
- **ENTRYPOINT unchanged in practice.** The image ENTRYPOINT now points at the Go binary directly. If your CI calls `/pipe/pipe.sh` explicitly, update it to either drop the explicit call (use the ENTRYPOINT) or call `/usr/local/bin/panora-versioning`.
- **Do not rely on shelling into the container to run bash scripts.** They are gone. Debug by running subcommands (`panora-versioning config-parse`, `panora-versioning detect-scenario`, etc.) against a merged config.
- **Bundled defaults moved.** `scripts/defaults.yml` → `config/defaults/defaults.yml` in the repo, mounted at `/etc/panora/defaults/defaults.yml` in the image. Override with `PANORA_DEFAULTS_DIR` for local/test runs.

---

## Initial values semantics

`version.components.*.initial` does NOT behave uniformly across all four components. The pipe treats namespace components (`epoch`, `major`) as **declarative authority** and progression components (`patch`, `hotfix_counter`) as **cold-start values only**. Understanding this asymmetry is required for consumers migrating from other tools, rotating epochs, or running sandbox isolation patterns.

| Component | Semantics | When `initial` takes effect |
|-----------|-----------|------------------------------|
| `epoch` | **Declarative authority** — defines the tag namespace | When `initial > 0` — restricts tag lookup to `^v{epoch}.{major}.*` |
| `major` | **Declarative authority** — defines the tag namespace | When `initial > 0` (or epoch > 0) — restricts tag lookup to the declared namespace |
| `patch` | **Cold-start only** — progression, not authority | Only when no tag exists in the configured namespace |
| `hotfix_counter` | **Cold-start only** — progression, not authority | Only when no tag exists in the configured namespace |

### Namespace filter threshold — `initial > 0` (ticket 059)

The namespace filter only activates when at least one of `epoch.initial` or `major.initial` is greater than zero. When both are `0` (the default), no namespace filter is applied and the pipe picks up the most recent matching tag regardless of its `vMAJOR` component. This prevents the silent reset bug that would occur for consumers using default config (`initial: 0`) who already have tags like `v0.2.0` or `v0.11.15`.

| `epoch.initial` | `major.initial` | Filter applied | Behavior |
|-----------------|-----------------|----------------|----------|
| `0` (default) | `0` (default) | None — prefix-only | Picks up most recent tag in the repo (e.g. `v0.11.15`), progresses from there |
| `0` (default) | `5` | `^v5\.` | Locks to `v5.*` namespace; cold-starts at `v5.0.1` if no `v5.*` tags exist |
| `1` | `0` | `^v1\.0\.` | Locks to `v1.0.*` namespace (epoch+major 2-component anchor) |
| `1` | `3` | `^v1\.3\.` | Locks to `v1.3.*` namespace |

### What `initial` means for progression components

| `initial` value | Existing tags in namespace | Behavior |
|-----------------|---------------------------|----------|
| `initial: 0` (default) | None | Cold start from 0 |
| `initial: 0` (default) | `v0.2.0`, `v0.11.15` | **Picks up most recent tag, progresses from there (no reset)** |
| `initial: 5` | `v0.2.0`, `v0.3.0` | Namespace isolation — cold start in `v0.5.*` ignoring existing tags |
| `initial: 5` | `v0.5.3`, `v0.5.4` | Progresses from `v0.5.4` within the declared namespace |

### What this means in practice

- **Default config consumers** — repo has `v0.2.0, v0.11.15` from prior releases with `initial: 0` (default). The pipe picks up `v0.11.15` and progresses normally. No reset, no silent data loss.
- **Migration from another tool** — repo has `v1.0.0, v1.5.2, v1.8.0` from a prior pipeline. You set `version.components.major.initial: 2` in `.versioning.yml`. The next tag is in the `v2.*` namespace (e.g. `v2.1.0` on a feat commit). The existing `v1.*` tags are not considered for progression.
- **Epoch rotation** — declare a new era of versioning by setting `version.components.epoch.initial: 1` and `version.components.major.initial: 0`. The next tag lands in the `v1.0.*` namespace regardless of any `v0.*` history.
- **Namespace isolation** — short-lived branches (sandboxes, preview environments, integration-test matrices) can each set a unique `major.initial` to isolate their tag namespaces from the main branch's history without manipulating tags.
- **Intentional downgrade** — setting `major.initial: 2` when the current highest tag is `v3.0.0` lands the next tag in the `v2.*` namespace. The pipe respects what you declared; it does not invent heuristics to override your config.
- **Progression `initial` with existing tags** — if tags already exist in the configured namespace, `patch.initial` and `hotfix_counter.initial` are ignored (progression continues from the latest matching tag). The pipe logs a diagnostic line when these values are set to a non-default (non-zero) value in that case.

### Rollback

The declarative behavior of namespace `initial` has no config flag to revert. If you need the pre-ticket-055 behavior of silently ignoring `epoch.initial` / `major.initial` when tags exist, pin an earlier container image (`panora-versioning-pipe:<pre-v0.12>`).

---

## Safety guardrails

The pipe includes a runtime enforcement layer that runs **after** version calculation and **before** tag emission. If an invariant is violated, the pipeline aborts with an actionable error before any tag, CHANGELOG, or push occurs.

### How it works

```
calc-version → /tmp/next_version.txt
       ↓
run-guardrails            ← enforcement layer (internal/guardrails)
       ↓ (pass)
write-version-file → CHANGELOG → tag → push
```

Each guardrail is a pure function: reads `/tmp/*.txt` and git state, never modifies anything, and emits a structured log line:

```
GUARDRAIL name=no_version_regression result=blocked violation=major_not_incremented bump=major next=v29.1.0 latest=v29.5.0
```

### assert_no_version_regression

Blocks emission when the computed tag is inconsistent with the declared bump type relative to the latest tag in the active namespace.

| Bump type | Rule |
|-----------|------|
| `epoch` (BREAKING CHANGE) | `next.epoch > latest.epoch` |
| `major` (feat) | `next.major > latest.major` + `next.epoch >= latest.epoch` |
| `patch` (fix) | `next.patch > latest.patch` + `next.major/epoch >= latest` |
| `hotfix` | Same base → `next.hotfix_counter > latest.hotfix_counter`<br>Base changed → all base components `>=` latest (counter free — reset is valid) |

Cold start (no latest tag in the active namespace) always passes. This handles both fresh repos and intentional namespace upgrades via `major.initial` / `epoch.initial`.

### Configuration

```yaml
validation:
  allow_version_regression: false  # default — block on regression
```

### Escape hatch (emergency override)

If the guardrail itself has a bug or is blocking a release you explicitly want (rare case: intentional downgrade, epoch rollback, or a calculation defect in the pipe), set `allow_version_regression: true` in `.versioning.yml`. The guardrail degrades from a hard block (exit 1) to an advisory warning (exit 0 with `GUARDRAIL ... result=warned` log). The tag is emitted anyway.

**This is the escape hatch.** A bug in the guardrail will never leave a consumer permanently stuck — flip the flag, ship the release, open an issue with the log line, then flip it back. The full recovery workflow is documented in [`docs/troubleshooting.md`](../troubleshooting.md#tag-on-merge-failed-with-version-regression-blocked-guardrail).

### When the guardrail fires

Common causes:
- A calculation bug in the pipe (future regression protection)
- Manual tag manipulation in the repo (deleted/recreated tags out of order)
- Fetching with a shallow clone that missed recent tags
- Misconfigured `version.components.*.initial` that would reset the namespace silently

The error message names the specific violation and the exact tags involved so the operator can diagnose quickly. See [`docs/troubleshooting.md`](../troubleshooting.md#tag-on-merge-failed-with-version-regression-blocked-guardrail) for the violation table and step-by-step recovery.

---

## Known limitations

1. **Bump strategy coupled to changelog.mode**: `mode: "last_commit"` uses last-commit-wins; `mode: "full"` uses highest-wins across all commits. There is no way to mix the two (intentional — they are semantically coherent). See "Bump calculation semantics" above.

2. **Array config values with spaces**: list values that contain spaces (e.g. regex patterns in `ignore_patterns`) must be quoted in YAML. Prefer anchored patterns without whitespace when possible.

3. **Tag format migration**: changing version format config (epoch, timestamp, v-prefix) causes old tags to be ignored. The pipe starts from `initial` values whenever the configured namespace (`epoch.initial` + `major.initial`) is empty — see "Initial values semantics" above for the full declarative vs cold-start rules.

4. **Orphaned hotfix generator (REMOVED in v0.6.3)**: the standalone hotfix changelog generator was deleted in PR #49 (ticket 031). The unified wire-up (ticket 024) already routed hotfix releases through `generate-changelog-last-commit` with a `(Hotfix)` header marker — the old generator was dead code.
