# Adoption Guide

**Last updated:** 2026-04-10 (v0.5.5)

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

## Next steps

- [`docs/architecture/README.md`](architecture/README.md) — how version calculation, CHANGELOG generation, and per-folder routing actually work under the hood.
- [`docs/per-folder-changelog/README.md`](per-folder-changelog/README.md) — deep dive for monorepo adopters (scope matching, subfolder discovery, `file_path` fallback).
- [`examples/`](../examples/) — every config and workflow shipped with the pipe; all are production-grade and tested.
- [`CONTRIBUTING.md`](../CONTRIBUTING.md) — only if you plan to contribute changes back to the pipe itself. Consumers do not need this.
