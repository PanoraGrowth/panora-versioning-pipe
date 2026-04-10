# Per-folder CHANGELOG — Historical Test Results (v0.2.2)

> **Status**: Historical record. These are the original manual test results from the per-folder CHANGELOG feature stabilization in **v0.2.2** (2026-04-07). The feature is now covered by the automated test suite — see [`docs/tests/README.md`](../tests/README.md) for the current coverage. This file is kept for traceability of the three bugs found and fixed during the initial rollout; it is **not** kept in sync with newer releases.

---

Test execution results for the per-folder CHANGELOG routing feature.

**Test plan reference:** `temp/999-testing/test-plan.md`, section 4.2 _(internal)_
**Execution date:** 2026-04-07
**Pipe version tested:** v0.2.2 (Docker image `:latest` at the time)
**Tester:** Claude + Agustin Manessi

**Test repos** _(one-off manual fixtures, no longer actively used)_:
- GitHub: `PanoraGrowth/panora-versioning-pipe-test`
- Bitbucket: `panoragrowth/panora-versioning-pipe-bitbucket`

---

## Summary

| Platform | Total | Passed | Failed | Bugs found |
|----------|-------|--------|--------|------------|
| GitHub | 34 | 34 | 0 | 3 (all fixed) |
| Bitbucket | 8 | 8 | 0 | 0 |
| **Total** | **42** | **42** | **0** | **3** |

### Bugs found and fixed during testing

| Bug | Found in test | Root cause | Fixed in | PR |
|-----|--------------|------------|----------|-----|
| All `chore` commits silently filtered | 4.2.12 | `^chore: update CHANGELOG` ignore pattern split by spaces into `^chore:` standalone | v0.2.1 | #20 |
| Multiple commits to same folder lost entries | 4.2.23 | awk `$0 == version` exact match failed on `## v0.12.0 - 2026-04-07` (includes date) | v0.2.2 | #21 |
| last_commit mode leaked non-last commits to root | 4.2.31 | Root script took `head -n 1` of filtered (non-routed) commits instead of ALL commits | v0.2.2 | #21 |

---

## GitHub Test Results

### Group A — Scope matches configured folder directly

| # | Test | Commit | Expected | GH result | Notes |
|---|------|--------|----------|-----------|-------|
| 4.2.1 | Suffix scope routes | `feat(cluster-ecs): add ECS task definition` | `infrastructure/001-cluster-ecs/CHANGELOG.md` | PASS | Log: `Scope 'cluster-ecs' → infrastructure/001-cluster-ecs/CHANGELOG.md` |
| 4.2.2 | Second suffix scope | `fix(networking): fix VPC peering configuration` | `infrastructure/002-networking/CHANGELOG.md` | PASS | Log: `Scope 'networking' → infrastructure/002-networking/CHANGELOG.md` |
| 4.2.3 | Exact scope match (backend) | `feat(backend): add shared utility function` | `backend/CHANGELOG.md`, NOT root | PASS | Log: `Scope 'backend' → backend/CHANGELOG.md` |
| 4.2.4 | Exact scope match (frontend) | `fix(frontend): fix responsive layout` | `frontend/CHANGELOG.md`, NOT root | PASS | Log: `All commits routed — no root CHANGELOG entry needed` |

### Group B — Subfolder discovery

| # | Test | Commit | Expected | GH result | Notes |
|---|------|--------|----------|-----------|-------|
| 4.2.5 | auth-service | `feat(auth-service): add OAuth support` | `backend/auth-service/CHANGELOG.md` | PASS | Subfolder discovery: scope matches existing subfolder name |
| 4.2.6 | api-gateway | `fix(api-gateway): fix route matching` | `backend/api-gateway/CHANGELOG.md` | PASS | |
| 4.2.7 | shared-libs | `chore(shared-libs): update utility functions` | `backend/shared-libs/CHANGELOG.md` | PASS | |
| 4.2.8 | web-app | `fix(web-app): fix login page redirect` | `frontend/web-app/CHANGELOG.md` | PASS | |
| 4.2.9 | mobile-app | `fix(mobile-app): fix navigation drawer` | `frontend/mobile-app/CHANGELOG.md` | PASS | |

### Group C — Fallback to parent folder

| # | Test | Commit | Expected | GH result | Notes |
|---|------|--------|----------|-----------|-------|
| 4.2.10 | Nonexistent subfolder (cloudfront) | `feat(cloudfront): add CDN configuration` | `backend/CHANGELOG.md` (fallback) | PASS | Log: `Scope 'cloudfront' → fallback file_path → backend/` |
| 4.2.11 | New subfolder created by commit | `feat(mac-app): create new macOS application` | `frontend/mac-app/CHANGELOG.md` | PASS | Pipe sees folder after checkout — discovery works on newly created folders |

### Group D — Outside configured folders

| # | Test | Commit | Expected | GH result | Notes |
|---|------|--------|----------|-----------|-------|
| 4.2.12 | Scope not in any folder | `fix(scripts): improve deploy error handling` | Root CHANGELOG only | PASS | Initially INCONCLUSIVE due to ignore pattern bug (v0.2.0), re-tested on v0.2.1 |
| 4.2.13 | Root-level files | `chore: update config` | Root CHANGELOG only | PASS | (covered via 4.2.15 test — paths-ignore caveat) |

### Group E — No scope

| # | Test | Commit | Expected | GH result | Notes |
|---|------|--------|----------|-----------|-------|
| 4.2.14 | No scope, files in folder | `feat: add utility helpers` | Root CHANGELOG only | PASS | No scope = no routing, even though files are in backend/ |
| 4.2.15 | No scope, files outside | `docs: update architecture documentation` | Root CHANGELOG only | PASS | Caveat: `paths-ignore: docs/**` in workflow prevents branch pipeline from running on docs-only changes |

### Group F — Edge cases

| # | Test | Commit | Expected | GH result | Notes |
|---|------|--------|----------|-----------|-------|
| 4.2.16 | Multiple folders touched | `feat(api): full stack API integration` | Root CHANGELOG only (ambiguous) | PASS | Scope doesn't match + files in multiple folders → root |
| 4.2.17 | fallback=root, subfolder exists | `feat(auth-service): improve OAuth token refresh` | `backend/auth-service/CHANGELOG.md` | PASS | Subfolder discovery wins BEFORE fallback is checked |
| 4.2.18 | fallback=root, no subfolder | `feat(cloudfront): configure CDN distribution` | Root CHANGELOG only | PASS | No subfolder, fallback=root skips file_path |
| 4.2.19 | Per-folder disabled | `feat(backend): test with per-folder disabled` | Root CHANGELOG only | PASS | Per-folder section entirely skipped in logs |
| 4.2.20 | Configured folder doesn't exist | `feat(noexiste): test nonexistent folder` | Root CHANGELOG only | PASS | Graceful skip, no error |

### Group G — Multi-commit: each to different folder

| # | Test | Commits | Expected | GH result | Notes |
|---|------|---------|----------|-----------|-------|
| 4.2.21 | 2 commits, 2 folders | `feat(backend)` + `fix(frontend)` | backend/ 1, frontend/ 1, root empty | PASS | Mode: full. `3 commit(s) routed` |
| 4.2.22 | 3 commits, 3 folders | `feat(backend)` + `fix(frontend)` + `feat(infrastructure)` | backend/ 1, frontend/ 1, infrastructure/ 1, root empty | PASS | Re-tested with correct folder name (initially used "infra" which didn't match) |

### Group H — Multi-commit: multiple to same folder

| # | Test | Commits | Expected | GH result | Notes |
|---|------|---------|----------|-----------|-------|
| 4.2.23 | 3 commits, 2 to same | `feat(backend)` + `fix(backend)` + `feat(frontend)` | backend/ 2, frontend/ 1, root empty | PASS | Initially FAILED (awk exact match bug), re-tested on v0.2.2 |
| 4.2.24 | 2 commits same subfolder | `feat(auth-service)` + `fix(auth-service)` | auth-service/ 2, root empty | PASS | Both entries under same version header |

### Group I — Mix routed + unrouted

| # | Test | Commits | Expected | GH result | Notes |
|---|------|---------|----------|-----------|-------|
| 4.2.25 | Routed + unrouted | `feat(backend)` + `docs:` + `fix(frontend)` | backend/ 1, frontend/ 1, root 1 | PASS | `docs:` has no scope → root |
| 4.2.26 | Scoped + no-scope same area | `feat(backend)` + `feat:` (no scope) | backend/ 1, root 1 | PASS | No scope always goes to root regardless of file location |
| 4.2.27 | All unrouted | `docs:` + `fix(scripts):` + `docs:` | Root 3 entries | PASS | scripts/ not configured, docs has no scope |

### Group J — Discovery + fallback mix

| # | Test | Commits | Expected | GH result | Notes |
|---|------|---------|----------|-----------|-------|
| 4.2.28 | Discovery + direct match | `feat(auth-service)` + `feat(backend)` | auth-service/ 1, backend/ 1 | PASS | Two different routing paths in same PR |
| 4.2.29 | Discovery + fallback | `feat(auth-service)` + `feat(cloudfront)` | auth-service/ 1, backend/ 1 (fallback) | PASS | auth-service via discovery, cloudfront via file_path fallback |
| 4.2.30 | Discovery + unrouted + fallback | `feat(web-app)` + `docs:` + `feat(monitoring)` | web-app/ 1, root 2 | PASS | monitoring → root (infrastructure not in folders config) |

### Group K — last_commit mode

| # | Test | Commits | Expected | GH result | Notes |
|---|------|---------|----------|-----------|-------|
| 4.2.31 | Last commit routed | `feat(backend)` + `fix(frontend)` (last) | frontend/ only | PASS | Initially FAILED (non-last leaked to root), re-tested on v0.2.2 |
| 4.2.32 | Last commit to subfolder | `feat(backend)` + `fix(auth-service)` (last) | auth-service/ only | PASS | First commit fully ignored |
| 4.2.33 | Last commit unrouted | `feat(backend)` + `docs:` (last) | Root only | PASS | No scope on last commit → root, first ignored |
| 4.2.34 | last_commit + per-folder off | `feat(backend)` + `fix(frontend)` (last) | Root only | PASS | Per-folder disabled, only last commit to root |

---

## Bitbucket Test Results

Core routing paths verified (subset of 8 tests covering all routing logic):

| # | Test | Commit | Expected | BB result | Notes |
|---|------|--------|----------|-----------|-------|
| 4.2.3 | Exact scope match | `feat(backend): add shared utility` | `backend/CHANGELOG.md` | PASS | |
| 4.2.5 | Subfolder discovery | `feat(auth-service): add OAuth module` | `backend/auth-service/CHANGELOG.md` | PASS | |
| 4.2.10 | Fallback file_path | `feat(cloudfront): add CDN config` | `backend/CHANGELOG.md` (fallback) | PASS | |
| 4.2.14 | No scope → root | `feat: add general feature` | Root CHANGELOG only | PASS | |
| 4.2.12 | Outside folders → root | `fix(scripts): fix deploy timeout` | Root CHANGELOG only | PASS | |
| 4.2.19 | Per-folder disabled | `feat(backend): test disabled mode` | Root CHANGELOG only | PASS | |
| 4.2.23 | Multi-commit same folder (full) | 3 commits: 2 backend, 1 frontend | backend/ 2, frontend/ 1 | PASS | |
| 4.2.31 | last_commit mode | `feat(backend)` ignored + `fix(frontend)` counts | frontend/ only | PASS | |

---

## Key behavioral observations

1. **Exclusive routing works**: no commit entry ever appeared in both a subfolder and root CHANGELOG
2. **Subfolder discovery works on newly created folders**: if a commit creates a folder, the pipe sees it after checkout
3. **Subfolder discovery takes priority over fallback**: even with `fallback: "root"`, if a matching subfolder exists, it gets the CHANGELOG
4. **Nonexistent configured folders are handled gracefully**: pipe skips silently, falls back to root
5. **Multiple folders touched = ambiguous = root**: no guessing when files span multiple configured folders
6. **No scope = always root**: no implicit routing based on file paths when scope is missing
7. **last_commit mode fully isolates**: non-last commits are completely invisible to both per-folder and root scripts
