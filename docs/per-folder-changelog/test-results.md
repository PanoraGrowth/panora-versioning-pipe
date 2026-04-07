# Per-folder CHANGELOG — Test Results

Test execution results for the per-folder CHANGELOG routing feature.

**Test plan reference:** `temp/999-testing/test-plan.md`, section 4.2

**Test repos:**
- GitHub: `PanoraGrowth/panora-versioning-pipe-test`
- Bitbucket: `panoragrowth/panora-versioning-pipe-bitbucket`

---

## Pre-test checklist

- [ ] Docker image `:latest` published with per-folder routing changes
- [ ] Test repos have folder structure matching test setup (section 4.2.A and 4.2.B in test plan)
- [ ] Test repos have clean state (no pending PRs, no dirty branches)
- [ ] Previous per-folder CHANGELOGs cleaned up from test repos

---

## Test execution

### Run 1 — Single commit tests (Groups A-F)

**Date:** _pending_
**Image version:** _pending_
**Tester:** Claude + user

#### Group A — Scope matches configured folder directly

| # | Test | GH result | BB result | Notes |
|---|------|-----------|-----------|-------|
| 4.2.1 | Suffix scope routes | | | |
| 4.2.2 | Second suffix scope | | | |
| 4.2.3 | Exact scope match | | | |
| 4.2.4 | Exact scope match 2 | | | |

#### Group B — Subfolder discovery

| # | Test | GH result | BB result | Notes |
|---|------|-----------|-----------|-------|
| 4.2.5 | Subfolder: auth-service | | | |
| 4.2.6 | Subfolder: api-gateway | | | |
| 4.2.7 | Subfolder: shared-libs | | | |
| 4.2.8 | Subfolder: web-app | | | |
| 4.2.9 | Subfolder: mobile-app | | | |

#### Group C — Fallback to parent folder

| # | Test | GH result | BB result | Notes |
|---|------|-----------|-----------|-------|
| 4.2.10 | Nonexistent subfolder | | | |
| 4.2.11 | Nonexistent subfolder 2 | | | |

#### Group D — Outside configured folders

| # | Test | GH result | BB result | Notes |
|---|------|-----------|-----------|-------|
| 4.2.12 | Scope not in any folder | | | |
| 4.2.13 | Root-level files | | | |

#### Group E — No scope

| # | Test | GH result | BB result | Notes |
|---|------|-----------|-----------|-------|
| 4.2.14 | No scope, files in folder | | | |
| 4.2.15 | No scope, files outside | | | |

#### Group F — Edge cases

| # | Test | GH result | BB result | Notes |
|---|------|-----------|-----------|-------|
| 4.2.16 | Multiple folders touched | | | |
| 4.2.17 | Fallback "root", subfolder exists | | | |
| 4.2.18 | Fallback "root", no subfolder | | | |
| 4.2.19 | Per-folder disabled | | | |
| 4.2.20 | Folder doesn't exist | | | |

### Run 2 — Multi-commit tests (Groups G-K)

**Date:** _pending_
**Image version:** _pending_
**Tester:** Claude + user

#### Group G — Each commit to different folder

| # | Test | GH result | BB result | Notes |
|---|------|-----------|-----------|-------|
| 4.2.21 | 2 commits, 2 folders | | | |
| 4.2.22 | 3 commits, 3 folders | | | |

#### Group H — Multiple commits to same folder

| # | Test | GH result | BB result | Notes |
|---|------|-----------|-----------|-------|
| 4.2.23 | 3 commits, 2 to same | | | |
| 4.2.24 | 2 commits same subfolder | | | |

#### Group I — Mix routed + unrouted

| # | Test | GH result | BB result | Notes |
|---|------|-----------|-----------|-------|
| 4.2.25 | Routed + unrouted | | | |
| 4.2.26 | Scoped + no-scope same area | | | |
| 4.2.27 | All unrouted | | | |

#### Group J — Discovery + fallback mix

| # | Test | GH result | BB result | Notes |
|---|------|-----------|-----------|-------|
| 4.2.28 | Discovery + direct match | | | |
| 4.2.29 | Discovery + fallback | | | |
| 4.2.30 | Discovery + unrouted + fallback | | | |

#### Group K — last_commit mode

| # | Test | GH result | BB result | Notes |
|---|------|-----------|-----------|-------|
| 4.2.31 | Last commit routed | | | |
| 4.2.32 | Last commit to subfolder | | | |
| 4.2.33 | Last commit unrouted | | | |
| 4.2.34 | Last commit, per-folder off | | | |

---

## Issues found

_Document any failures here with: test number, expected vs actual, error logs, criticality (CRITICAL/HIGH/LOW)._

| # | Test | Criticality | Expected | Actual | Root cause | Fixed in |
|---|------|-------------|----------|--------|------------|----------|
| | | | | | | |

---

## Summary

| Metric | Value |
|--------|-------|
| Total tests | 34 |
| Passed (GH) | _pending_ |
| Passed (BB) | _pending_ |
| Failed | _pending_ |
| Issues found | _pending_ |
