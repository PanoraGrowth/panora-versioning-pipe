# Integration test sandbox architecture

Developer-facing reference for the 20-sandbox parallel integration harness. Not consumer-facing — this is for contributors who touch `tests/integration/`, the test repo, or the `tag-on-merge.yml` workflow.

Test repo: [`PanoraGrowth/panora-versioning-pipe-test`](https://github.com/PanoraGrowth/panora-versioning-pipe-test).

---

## 1. Overview

### Problem

The original integration suite ran ~15 scenarios sequentially against a single `main` branch in the test repo. Each scenario:

1. Created a `test/auto-*` branch
2. Opened a PR to `main`
3. Merged it
4. Waited for `tag-on-merge.yml` to tag `main`
5. Verified the tag, then cleaned up

Total wall-clock: **~2 hours**. Bottleneck wasn't CPU — it was contention. Every scenario fought for the same `main` ref and the same tag namespace. Parallelizing was impossible.

### Solution

20 permanent sandbox branches (`sandbox-01` … `sandbox-20`) in the test repo. Each owns a disjoint tag namespace (`vN.*`) via a unique `major.initial` in its `.versioning.yml`. Scenarios pytest-xdist-parallelize across the sandboxes with zero collisions.

Target wall-clock: **~15–20 min for 26 scenarios**.

---

## 2. How sandboxes isolate state

Each sandbox-NN branch has its own `.versioning.yml` with `major.initial: N`. Tags produced under sandbox-07 are always `v7.*.*`; under sandbox-09, `v9.*.*.1`. Tag namespaces never overlap, so two workers running in parallel can never produce the same tag or confuse each other's latest.

Lifecycle of a single merge scenario:

1. Fork a temp branch `test/auto-{scenario}-{run_id}` **from its sandbox** (not from `main`).
2. Commit the scenario's files to that temp branch.
3. Open a PR targeting the sandbox.
4. Merge the PR (squash or merge — driven by `merge_method`).
5. `tag-on-merge.yml` fires on the sandbox push and tags it.
6. Verify the tag matches `tag_pattern` (e.g. `^v7\.\d+\.\d+$`).
7. `finally` block deletes the temp branch and the created tag. The sandbox ref is left where it was (the CHANGELOG commit stays — it doesn't affect anything).

Sandbox branches are never merged into each other. They exist in parallel as independent tag universes.

PR-only scenarios (no merge, just PR validation) still target `main` — they don't need a sandbox because they don't push anything.

---

## 3. Sandbox map

Source of truth: [`tests/integration/test-scenarios.yml`](../../tests/integration/test-scenarios.yml) — `base:` field on each scenario.

| # | Scenario | `major.initial` | Expected tag | Merge / flow |
|---|---|---|---|---|
| 01 | feat-minor-bump | 1 | `v1.x.x` | squash |
| 02 | fix-patch-bump | 2 | `v2.x.x` | squash |
| 03 | scoped-backend | 3 | `v3.x.x` | squash |
| 04 | scoped-frontend | 4 | `v4.x.x` | squash |
| 05 | unscoped-to-root | 5 | `v5.x.x` | squash |
| 06 | multi-commit-last-wins | 6 | `v6.x.x` | merge (preserve commits) |
| 07 | full-mode-all-typed-passes | 7 | `v7.x.x` | squash |
| 08 | tag-on-main-development-release | 8 | `v8.x.x` | squash |
| 09 | hotfix-to-main-extended-targets | 9 | `v9.x.x.1` | squash, hotfix |
| 10 | hotfix-to-main-with-patch-bump | 10 | `v10.x.x.1` | squash, hotfix |
| 11 | hotfix-scoped-patch-bump | 11 | `v11.x.x.1` | squash, hotfix |
| 12 | hotfix-patch-bump-regression | 12 | `v12.x.x.1` | squash, hotfix |
| 13 | hotfix-uppercase-branch-prefix | 13 | `v13.x.x.1` | squash, hotfix (Hotfix/ prefix) |
| 14 | feat-minor-bump-semver | 14 | `v14.x.x` | squash |
| 15 | fix-patch-bump-semver | 15 | `v15.x.x` | squash |
| 16 | per-folder-suffix-matching | 16 | `v16.x.x` | squash |
| 17 | per-folder-fallback-file-path | 17 | `v17.x.x` | squash |
| 18 | per-folder-multi-folder-write | 18 | `v18.x.x` | squash |
| 19 | version-file-groups-trigger-match | 19 | `v19.x.x` | squash |
| 20 | version-file-groups-trigger-no-match | 20 | `v20.x.x` | squash |

PR-only scenarios (no sandbox, base = `main`): `chore-minor-bump`, `invalid-commit-format`, `full-mode-untyped-intermediate-fails`, `hotfix-from-production-branch`, `hotfix-custom-target-pr-check`, `refactor-no-bump`.

---

## 4. Config override layering

Two layers are deep-merged at runtime:

1. **Base** — the sandbox's committed `.versioning.yml`. Contains `major.initial=N`, `branches.tag_on=sandbox-NN`, `hotfix_targets=[sandbox-NN]`, `per_folder` baseline, etc. Built by `seed-sandboxes.sh::build_versioning_yml*()`.
2. **Override** — each scenario's `config_override` in `test-scenarios.yml`. Deep-merged on top of the base. Only specify keys that differ.

Example — scenario 11 (hotfix-scoped-patch-bump):

```yaml
config_override:
  branches:
    tag_on: sandbox-11
    hotfix_targets:
      - "sandbox-11"
  version:
    components:
      hotfix_counter:
        enabled: true
```

Everything else (`major.initial: 11`, `changelog.mode`, `hotfix.keyword`, etc.) comes from the sandbox's baseline.

Deep-merge implementation: [`tests/integration/conftest.py::deep_merge`](../../tests/integration/conftest.py).

Rule of thumb: **never set `major.initial` in an override**. The sandbox owns it. If you need a different major for a new scenario, seed a new sandbox.

---

## 5. The `tag-on-merge.yml` change (test repo)

Two edits in the test repo's workflow so sandbox pushes get tagged correctly:

- **Trigger** — `on.push.branches` now includes `sandbox-*` (previously `main` only).
- **Checkout ref** — uses `${{ github.ref_name }}` instead of hardcoded `main`. This makes the pipe read `.versioning.yml` from the sandbox that was just pushed, not from `main`. Without this fix, every sandbox would produce tags against `main`'s config — back to square one.

The `workflow_dispatch` fallback also accepts a `ref` input and `GitHubClient.dispatch_tag_workflow(ref=...)` passes it through. See [`tests/integration/helpers/github_client.py:202`](../../tests/integration/helpers/github_client.py).

---

## 6. Special fixtures (sandboxes 16–20)

Some scenarios need directory structure that doesn't exist on `main`. Seeded once per sandbox by `seed-sandboxes.sh`; the scripts are idempotent (check existing file SHA, skip if present).

| Sandbox | Fixture files | Exercises |
|---|---|---|
| 16 | `services/001-cluster-ecs/README.md` | `per_folder.scope_matching: suffix` end-to-end — `feat(cluster-ecs)` routes changelog to `services/001-cluster-ecs/` |
| 17 | `backend/README.md`, `frontend/README.md` | `per_folder.fallback: file_path` — unscoped commit in `backend/` routes to `backend/CHANGELOG.md` |
| 18 | `backend/README.md`, `frontend/README.md` | `per_folder.fallback: file_path` multi-folder write — commit touching both writes two CHANGELOGs |
| 19 | `services/version.yaml`, `services/README.md`, `services/main.tf` | `version_file.groups.trigger_paths` matches — version file gets updated |
| 20 | `services/version.yaml`, `services/README.md`, `infrastructure/README.md` | `version_file.groups.trigger_paths` does NOT match — version file stays untouched |

Sandbox 16 also swaps its base config (`scope_matching: suffix`, `fallback: root`, `folders: [services]`) because the default would collide with scenarios 17/18. See `build_versioning_yml_16()` in [`seed-sandboxes.sh`](../../tests/integration/tools/seed-sandboxes.sh).

Sandboxes 19/20 disable `per_folder` entirely and enable `version_file.groups` with `trigger_paths: services/**`.

---

## 7. Harness changes

| File | Change |
|---|---|
| [`tests/integration/helpers/github_client.py`](../../tests/integration/helpers/github_client.py) | `dispatch_tag_workflow(ref=...)`, `get_latest_workflow_run_id(branch=...)`, `wait_for_tag_workflow(branch=...)`, `get_latest_tag(prefix=...)`, `wait_for_new_tag(prefix=...)` — all parameterized so workers only see their own sandbox's state |
| [`tests/integration/conftest.py`](../../tests/integration/conftest.py) | `sandbox_major(base)` helper — parses `sandbox-NN` → `N`, returns 0 for `main`. Each worker gets its own `uuid4()` `run_id` → no cross-worker branch name collisions |
| [`tests/integration/test_github.py`](../../tests/integration/test_github.py) | `base = scenario.get("base", "main")` — replaces hardcoded `"main"` in PR creation (lines 38, 99) |
| [`Makefile`](../../Makefile) | `test-integration` now runs `pytest -n auto --dist loadscope test_github.py` |
| [`tests/integration/requirements.txt`](../../tests/integration/requirements.txt) | Added `pytest-xdist>=3.5.0` |

`--dist loadscope` groups tests by module/class so PR-only and merge-scenario groups don't ping-pong across workers.

---

## 8. Adding a new scenario

If an existing sandbox covers your config, just add a scenario entry pointing to it. Otherwise seed a new sandbox:

1. **Pick the next sandbox number** — currently 1–20 are used. Add 21 (and bump the max check in `seed-sandboxes.sh::main()` — today it caps at 20).
2. **Extend `seed-sandboxes.sh`** — if your scenario needs custom base config or fixtures, add a `build_versioning_yml_21()` and a `seed_sandbox_21()` like 16–20. Otherwise the generic `build_versioning_yml "$n"` is fine.
3. **Run the seeder**: `./tests/integration/tools/seed-sandboxes.sh 21` (single-sandbox mode, idempotent). Verify with `--dry-run` first.
4. **Add to `sandbox-audit.sh`** if the sandbox has special fixtures — add a `case` arm in the fixtures check.
5. **Add the scenario to [`test-scenarios.yml`](../../tests/integration/test-scenarios.yml)**:
   ```yaml
   - name: my-new-scenario
     description: "..."
     base: sandbox-21
     config_override:
       branches:
         tag_on: sandbox-21
       # any other deltas
     commits:
       - message: "feat: ..."
         files:
           some/file.txt: "content"
     expected:
       pr_check: pass
       tag_created: true
       tag_pattern: "^v21\\.\\d+\\.\\d+$"
       changelog_contains: "..."
   ```
6. **Run it solo**: `make test-integration-filter S=my-new-scenario` (sequential, easier to debug).
7. **Run the full suite**: `make test-integration`.
8. **Update `docs/tests/DRAFT-coverage.md`** — flip the relevant ❌ to ✅.

---

## 9. Tooling

### [`seed-sandboxes.sh`](../../tests/integration/tools/seed-sandboxes.sh)

Idempotent creation/update of the 20 sandbox branches. Uses the `gh` CLI and the GitHub Contents + Git Data APIs — no local clone needed.

```bash
./seed-sandboxes.sh              # create/update all 20
./seed-sandboxes.sh 7            # only sandbox-07
./seed-sandboxes.sh --dry-run    # print what would happen, no API calls
```

Requirements: authenticated `gh`, `jq`, `base64`. POSIX-ish, shellcheck-clean. Safe to rerun — existing branches get their `.versioning.yml` updated in place; missing fixtures are added; present fixtures are left alone.

### [`sandbox-audit.sh`](../../tests/integration/tools/sandbox-audit.sh)

Post-hoc validator. Walks all 20 sandboxes and checks:

1. Branch exists.
2. `.versioning.yml` is present and `major.initial == N`.
3. `tag_on` points to its own sandbox.
4. Special fixtures for 16–20 are present.
5. No leftover tags in the `vN.*` namespace (warns — stale tags from past runs).
6. No orphan `test/auto-*` temp branches repo-wide (warns — cleanup gone wrong).

```bash
./sandbox-audit.sh       # audit all 20
./sandbox-audit.sh 14    # audit only sandbox-14
```

Not wired into CI. Run manually for operational hygiene, after a failed CI run, or before a release of the pipe itself.

---

## 10. Debugging

**Single scenario, sequential**: `make test-integration-filter S=hotfix-to-main-with-patch-bump`. This stays sequential (no `-n auto`) so you get clean logs and deterministic order.

**Deterministic order across the full suite**: pytest-xdist randomizes worker assignment. Add `-p no:randomly` if you need reproducibility, or run with `-n 0` to disable parallelism entirely.

**Workflow failure on a specific sandbox**: `gh run list -R PanoraGrowth/panora-versioning-pipe-test --branch sandbox-09 --workflow tag-on-merge.yml`. Each sandbox has its own run history, so you won't get flooded with unrelated runs.

**Stale state**: run `sandbox-audit.sh` to spot leftover tags or orphan `test/auto-*` branches. Clean them manually with:

```bash
gh api repos/PanoraGrowth/panora-versioning-pipe-test/git/refs/tags/v9.0.0.1 --method DELETE
gh api repos/PanoraGrowth/panora-versioning-pipe-test/git/refs/heads/test/auto-foo-abcd1234 --method DELETE
```

**Config drift** — if a sandbox's `.versioning.yml` got out of sync, reseed: `./seed-sandboxes.sh 09`. It replaces the file with the canonical version from the seeder.

---

## 11. Performance

| Metric | Before | After |
|---|---|---|
| Scenarios | ~15 | 26 |
| Wall-clock | ~2 h | ~15–20 min (target) |
| Parallelism | 1 | up to 20 (pytest-xdist `-n auto`) |
| GHA concurrency budget | n/a | 60 jobs (Team plan) — 20 used, comfortable margin |

`-n auto` maps to the CPU count of the machine running pytest, not to 20 — on a typical dev laptop that's 8–12 workers, which is fine because each test spends most of its time blocked waiting for GitHub Actions. The hard ceiling is GitHub's concurrent-job limit (60), not local CPU.

If you scale past 60 sandboxes, you'll need to chunk runs or upgrade the GHA plan — but that's a future problem.
