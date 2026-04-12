# Adoption Guide

**Last updated:** 2026-04-12 (platform-agnostic hotfix detection, ticket 031)

This guide walks a new consumer repository through adopting `panora-versioning-pipe` end-to-end: prerequisites, config selection, workflow installation, and verification of the first release. It assumes familiarity with git, GitHub Actions, and conventional commits, but assumes nothing about this pipe.

For deeper reference material, see:

- [`docs/architecture/README.md`](architecture/README.md) — how the pipe computes versions and routes CHANGELOG entries
- [`docs/github-app-setup.md`](github-app-setup.md) — the single hardest prerequisite (GitHub App creation)
- [`docs/troubleshooting.md`](troubleshooting.md) — common problems and fixes
- [`examples/`](../examples/) — canonical config and workflow files

---

## Prerequisites

Before you open the first PR:

- **GitHub App installed on the target repo**, granting `Contents: Read and write`. The default `GITHUB_TOKEN` cannot push past branch protection nor re-trigger downstream workflows — a GitHub App token bypasses both. See [`docs/github-app-setup.md`](github-app-setup.md) for step-by-step creation and installation.
- **Two repository secrets configured**: `CI_APP_ID` (numeric App ID) and `CI_APP_PRIVATE_KEY` (full PEM contents). The `tag-on-merge` workflow reads both via `actions/create-github-app-token@v1`.
- **Main branch protection** that allows the bot to push. Either (a) add the GitHub App as a bypass actor under Settings → Branches → main → "Allow specific actors to bypass pull request requirements", or (b) leave `main` unprotected (acceptable for internal tools, not for production repos). Without this, `tag-on-merge` will fail with "Unable to push to main" — see [`troubleshooting.md`](troubleshooting.md).
- **No existing `.versioning.yml` or `CHANGELOG.md`** (recommended for a clean bootstrap). If a `CHANGELOG.md` already exists, the pipe appends to it instead of recreating it — the first run will insert a new section at the top under the existing title. If a `.versioning.yml` already exists from a previous attempt, review it carefully against this guide before continuing.

---

## Step 1 — Choose your config

The pipe ships four example configs under [`examples/configs/`](../examples/configs/). Each one is a working starting point. Pick the closest match and copy it to `.versioning.yml` in your repo root.

| Config | When to pick it |
|--------|-----------------|
| [`versioning-minimal.yml`](../examples/configs/versioning-minimal.yml) | You want to try the pipe with zero configuration. Uses ticket format + the default version scheme (`MAJOR.MINOR.TIMESTAMP`). |
| [`versioning-conventional.yml`](../examples/configs/versioning-conventional.yml) | Most single-repo cases. Conventional commits (`feat(scope): msg`), clean tags like `v1.2.3`, emoji changelog, `docs` commits excluded from version bumps. |
| [`versioning-ticket.yml`](../examples/configs/versioning-ticket.yml) | Your team uses Jira (or a similar tracker) and every commit must carry a ticket prefix. Includes clickable Jira links in the CHANGELOG. |
| [`versioning-monorepo.yml`](../examples/configs/versioning-monorepo.yml) | Per-folder CHANGELOGs and grouped version file updates. Requires `commits.format: "conventional"`. |

### Recommended starter for a simple single-repo (npm / Astro / similar)

For a project like `it-services-site`, the smallest workable config is:

```yaml
commits:
  format: "conventional"

version:
  tag_prefix_v: true

commit_type_overrides:
  docs:
    bump: "none"

changelog:
  file: "CHANGELOG.md"
  use_emojis: true
  include_commit_link: true
  include_author: true
  commit_url: "https://github.com/your-org/your-repo/commit"

branches:
  tag_on: "main"
```

Three decisions worth understanding:

- **`version.tag_prefix_v: true`** — produces tags like `v1.2.3`. The npm and Astro ecosystems expect the `v` prefix by convention; set this to `false` if your release tooling parses the tag as a bare semver.
- **`commit_type_overrides.docs.bump: "none"`** — documentation-only commits won't trigger a release. This is the pattern the pipe itself uses.
- **`branches.tag_on: "main"`** — single-trunk workflow. If you use a dev/main flow, set it to `development` instead; see `scripts/defaults.yml` for the full branch model.

All other keys inherit from [`scripts/defaults.yml`](../scripts/defaults.yml). You only override what you need.

---

## Step 2 — Add the workflows

Copy the two example workflows verbatim into `.github/workflows/`:

- [`examples/github-actions/pr-versioning.yml`](../examples/github-actions/pr-versioning.yml) → `.github/workflows/pr-versioning.yml`. Runs on every PR. Validates commit format, generates a CHANGELOG preview, and pushes the preview commit back to the feature branch. Uses the default `GITHUB_TOKEN`; no GitHub App needed on the PR side.
- [`examples/github-actions/tag-on-merge.yml`](../examples/github-actions/tag-on-merge.yml) → `.github/workflows/tag-on-merge.yml`. Runs on push to `main`. Generates a GitHub App token, checks out `main`, runs the pipe, and atomically pushes a CHANGELOG commit and the new version tag in a single `git push`.

Both files follow the **inline single-job pattern**: one job, linear steps, no reusable-workflow indirection. This was a deliberate choice (`Finding #17` in the internal review log) — reusable workflows with a single caller add indirection without reuse payoff, so they were removed.

Change `branches: [main]` in both files if your tag branch is different.

---

## Step 3 — First PR and first release

### On the first PR

1. Open a PR against `main` with a properly formatted commit subject (e.g. `feat: initial release setup`).
2. `pr-versioning.yml` runs. It validates the commit format, computes what the next version would be, writes a `CHANGELOG.md` section for the last commit, commits it with a CI-skip marker, and pushes the commit back to the feature branch.
3. You'll see a new commit on your feature branch authored by `CI Pipeline` (or whatever you set via `GIT_USER_NAME`). Your PR diff now includes the CHANGELOG preview.

If this step fails, the commit subject is almost always the culprit. See "invalid commit format" in [`troubleshooting.md`](troubleshooting.md#pr-validation-failed-with-invalid-commit-format).

### On the first merge to `main`

1. Merge the PR (squash merge recommended — see Step 4).
2. `tag-on-merge.yml` runs. It generates a short-lived GitHub App token, checks out `main` using that token, runs the pipe container, computes the version, writes the final CHANGELOG, creates an annotated tag, and pushes the commit + tag atomically in one `git push`.
3. The atomic CHANGELOG commit carries the CI-skip marker in its subject so the push does NOT re-trigger `tag-on-merge.yml` (no infinite loop).

The whole flow usually takes 30–60 seconds.

---

## Step 4 — Verification

After the first merge to `main` completes, verify:

1. **Git tag exists**:

   ```bash
   git fetch --tags
   git tag --list | tail -1
   ```

   You should see a new tag — `v0.1.0` (or similar) if you set `tag_prefix_v: true`, or a bare `1.3.20260410143022` timestamp tag if you kept the default timestamp mode.

2. **`CHANGELOG.md` exists on `main`** and has an entry for the new version:

   ```bash
   git checkout main && git pull
   head -20 CHANGELOG.md
   ```

3. **The `tag-on-merge` workflow succeeded** with no "Unable to push to main" errors:

   ```bash
   gh run list --workflow tag-on-merge.yml --limit 1
   ```

4. **No infinite loop** — `tag-on-merge` ran once, not twice. If it ran twice, the CI-skip marker is missing from the CHANGELOG commit (the pipe adds it automatically; absence is a bug). Open an issue.

5. **Squash-merge the PR** if you're not already doing so. The pipe uses "last commit wins" for bump resolution (see [`architecture/README.md`](architecture/README.md#version-system)). With a squash merge, the only commit is the squash commit, and its subject determines the bump — which is exactly what you want. Merge commits leak intermediate commit types and produce surprising bumps (see [`troubleshooting.md`](troubleshooting.md#multi-commit-pr-produced-a-minor-bump-but-i-expected-major)).

---

## Common pitfalls

1. **`tag-on-merge` did not fire after merging to `main`.** Almost always caused by the CI skip marker substring appearing as descriptive text in the squash commit body. GitHub does a plain substring match on the whole commit message and skips all workflows. Fix: keep the marker out of PR titles and bodies. See [`troubleshooting.md`](troubleshooting.md#tag-on-merge-workflow-did-not-run-after-merging-to-main).
2. **"Unable to push to main" from `tag-on-merge`.** Branch protection doesn't allow the GitHub App to bypass PR requirements. See [`troubleshooting.md`](troubleshooting.md#tag-on-merge-failed-with-unable-to-push-to-main).
3. **Docker image pull fails with "manifest unknown".** The ECR Public alias (`k5n8p2t3`) is AWS auto-generated and will eventually transition to `panoragrowth`. Pin to a version tag (e.g. `:v0.5.5`) in production. See [`troubleshooting.md`](troubleshooting.md#docker-image-pull-failed-manifest-unknown).
4. **Multi-commit PR produces an unexpected bump.** The pipe uses last-commit-wins, not highest-wins. Use squash merges. See [`troubleshooting.md`](troubleshooting.md#multi-commit-pr-produced-a-minor-bump-but-i-expected-major).
5. **`commit_type_overrides` is ignored.** Usually a typo in the key name or a type not present in `scripts/defaults.yml`. See [`troubleshooting.md`](troubleshooting.md#my-config-has-commit_type_overrides-but-the-override-is-ignored).

---

## Step 5 — When and how to use hotfixes

Hotfixes are a dedicated release lane for urgent production fixes. They bump a separate PATCH component (not MINOR), so a hotfix released on top of `v0.5.9` becomes `v0.5.9.1` instead of `v0.5.10`. This keeps the next planned minor release on its own version number and makes rollback trivial.

**Default behavior (v0.6.3+)**: the hotfix flow is ON by default. You don't need to enable anything — just follow the commit convention below. To opt out (if your repo uses a 3-component version scheme), set `version.components.patch.enabled: false` in `.versioning.yml`.

**Detection is platform-agnostic**: pure git, no APIs. Works identically on GitHub Actions, Bitbucket Pipelines, GitLab CI, or any git host.

### When a hotfix is appropriate

- **Yes:** a production bug that can't wait for the next regular release cycle (security bypass, outage, data corruption).
- **No:** a routine bug you'd normally ship in the next release — use a normal `fix:` commit on the development branch.

### How to ship a hotfix (GitHub example)

1. **Create a branch off `main`** using the hotfix/ prefix by convention (the branch name is a human signal, the actual detection fires on the commit subject below):

   ```bash
   git checkout main && git pull
   git checkout -b hotfix/patch-auth-bypass
   ```

2. **Commit the fix with a `hotfix:` prefix** (this is the signal the pipe detects):

   ```bash
   git commit -m "hotfix: patch auth token leak"
   git push origin hotfix/patch-auth-bypass
   ```

3. **Open a PR to `main`**. **The PR title MUST start with `hotfix:`** — e.g. `hotfix: patch auth token leak`. This is because squash merge (recommended) uses the PR title as the squash commit subject, and the pipe's detection reads the merge commit subject post-merge.

4. **Squash-merge** the PR. GitHub creates a commit on `main` with subject `hotfix: patch auth token leak (#NN)`. The `(#NN)` suffix does not break the prefix match.

5. **Result**: the pipe runs, detects `hotfix` scenario from the commit subject, bumps PATCH, creates a tag like `v0.5.9.1`, and commits a CHANGELOG entry headed `## v0.5.9.1 (Hotfix) - YYYY-MM-DD`.

### How to ship a hotfix (Bitbucket example)

Identical to the GitHub flow above. Create a branch, commit with `hotfix:` prefix, push, open PR on Bitbucket, set the PR title to start with `hotfix:`, and use the squash merge option. The pipe detects the signal via the same `git log -1 --format='%s' HEAD` check and behaves identically.

### Merge styles and detection

| Merge style | What HEAD.subject is after merge | Hotfix detection fires if... |
|---|---|---|
| Squash merge (recommended) | PR title (e.g. `hotfix: fix foo (#42)`) | **PR title** starts with `hotfix:` or `hotfix(` |
| Rebase merge | Last replayed commit subject | **Last commit on the branch** starts with `hotfix:` or `hotfix(` |
| Merge commit (traditional 3-way) | `Merge pull request #42 from ...` | The pipe auto-inspects the **branch tip** (merge commit's second parent). If ANY commit on the branch tip is `hotfix:`, detection fires. |

### Custom keyword

If your team uses a different convention (e.g. `urgent:`, `critical:`, `fixprod:`), configure it in `.versioning.yml`:

```yaml
hotfix:
  keyword: "urgent"
```

Then commit with `urgent: fix critical bug` and set your PR title the same way. The pipe detects strictly on the configured keyword — `urgent:` matches, `hotfix:` does NOT match (unless you configure both).

### Opting out

If your repo doesn't need a 4th version component, opt out explicitly:

```yaml
version:
  components:
    patch:
      enabled: false
```

Hotfix commits will then be detected but treated as a no-op: the pipe emits a 3-line INFO log and skips tag creation. This is useful for repos that use `hotfix:` as a documentation label but don't want a distinct PATCH release channel.

### Rollback

Every hotfix produces a distinct Docker image tag, so rolling back is a straight `docker pull`:

```bash
docker pull ghcr.io/panoragrowth/panora-versioning-pipe:v0.5.9    # pre-hotfix
# or
docker pull ghcr.io/panoragrowth/panora-versioning-pipe:v0.5.9.1  # post-hotfix
```

The next minor release resets PATCH to 0 and omits it from the tag: `v0.5.9.2` → `v0.5.10`.

---

## Next steps

- [`docs/architecture/README.md`](architecture/README.md) — how version calculation, CHANGELOG generation, and per-folder routing actually work under the hood. See the "Hotfix flow" section for the full detection matrix.
- [`docs/per-folder-changelog/README.md`](per-folder-changelog/README.md) — deep dive for monorepo adopters (scope matching, subfolder discovery, `file_path` fallback).
- [`examples/`](../examples/) — every config and workflow shipped with the pipe; all are production-grade and tested.
- [`CONTRIBUTING.md`](../CONTRIBUTING.md) — only if you plan to contribute changes back to the pipe itself. Consumers do not need this.
