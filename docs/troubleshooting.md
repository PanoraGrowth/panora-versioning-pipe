# Troubleshooting

**Last updated:** 2026-04-11 (hotfix wire-up, ticket 024)

Common problems encountered by consumers of `panora-versioning-pipe`, with a short cause/fix note for each. Structure: one subsection per problem, each with **Cause**, **Fix**, and references to deeper material where relevant.

Tooling frustration is real. Most of the issues below are one-line fixes once you know what to look for — but you have to know what to look for.

---

## PR validation failed with "invalid commit format"

**Cause.** The last commit in the PR (or the commit on the feature branch that triggered the run) does not match the configured `commits.format`. The default format is `ticket` (`PROJ-123 - feat: message`); if you copied [`examples/configs/versioning-conventional.yml`](../examples/configs/versioning-conventional.yml), it is `conventional` (`feat(scope): message`).

**Fix.** Rewrite the commit subject to match the configured format. For conventional commits, use `type(scope): description` where `type` is one of the values in [`scripts/defaults.yml`](../scripts/defaults.yml) (`feat`, `fix`, `refactor`, `perf`, `docs`, `test`, `chore`, `build`, `ci`, `revert`, `style`, `hotfix`, `security`, `breaking`). The scope in parentheses is optional.

Then force-push the amended commit:

```bash
git commit --amend -m "feat: short description of the change"
git push --force-with-lease
```

**Advanced — ticket format.** If your project uses a ticket tracker, the subject must start with the ticket prefix: `PROJ-123 - feat: message`. If `tickets.required: true` is set, an unprefixed commit is rejected even if the rest of the format is valid. Verify `tickets.prefixes` and `tickets.required` in your `.versioning.yml` match what the team is actually writing. See also: [conventional commits spec](https://www.conventionalcommits.org/).

---

## tag-on-merge workflow did not run after merging to main

This is the most common post-adoption surprise, and it has three distinct causes. Walk them in order.

### Cause 1 — the CI skip marker substring in the commit message

GitHub Actions scans every push commit message for the literal substring `[skip ci]` (and variants: `[ci skip]`, `[no ci]`, `[skip actions]`, `[actions skip]`) and skips **all** workflows on that push if any is found. The match is a **plain substring match** — it makes no distinction between a directive and descriptive prose that happens to contain the same characters. The pipe's own CHANGELOG commits deliberately use this marker to prevent re-triggering (see [`scripts/changelog/update-changelog.sh`](../scripts/changelog/update-changelog.sh)), but humans describing that behavior in their own commit bodies trigger the same skip by accident.

**Incident context.** This is Finding #16 in the internal review log. PR #34 was merged with descriptive text explaining the marker behavior in the PR body. The squash-merge commit inherited the body, GitHub substring-matched the skip marker, and `tag-on-merge.yml` never queued. The PR landed on `main` with no tag and no CHANGELOG. Recovery required bundling the missed changes into the next release via PR #35.

**Fix.** Verify the squash commit message is clean:

```bash
git log main -1 --format='%B'
```

If you see `[skip ci]`, `[ci skip]`, `[no ci]`, `[skip actions]`, or `[actions skip]` anywhere in the output, the workflow was skipped intentionally by GitHub. Both the PR title and the PR body contribute to the squash commit message by default — sanitize both before merging. The [`CONTRIBUTING.md`](../CONTRIBUTING.md#commit-message-hygiene) "Commit Message Hygiene" section lists safe alternative phrasings when you need to document the marker's behavior in a commit.

**Recovery when it has already happened.** You cannot re-trigger a skipped workflow manually — GitHub does not offer that. The only path forward is to merge a subsequent PR whose squash message is clean. The next `tag-on-merge` run will bundle the previously skipped changes and the new ones into one release. The lost PR's changes will be credited to the second merge in the CHANGELOG — not ideal, but unavoidable.

### Cause 2 — a `paths-ignore` filter on the workflow trigger

**Cause.** Someone added a `paths-ignore` block to `.github/workflows/tag-on-merge.yml` (e.g. to skip doc-only changes). If the merged push only touches files matched by the filter, the whole workflow is skipped at the trigger level.

**Fix.** The canonical [`examples/github-actions/tag-on-merge.yml`](../examples/github-actions/tag-on-merge.yml) has **no `paths-ignore`** — this is deliberate (Finding #18 in the internal review log: versioning decisions belong in the pipe config via `commit_type_overrides`, not in the workflow trigger). Remove any `paths-ignore` your team has added. If you want documentation commits to skip the bump, set `commit_type_overrides.docs.bump: "none"` in `.versioning.yml` instead.

### Cause 3 — branch protection rejected the GitHub App push

**Cause.** The workflow started, generated a token, ran the pipe, tried to push — and the push was rejected by branch protection. From the GitHub Actions UI the workflow looks like it "didn't run" because you're scanning for success/failure on the final step and missed an earlier push rejection.

**Fix.** Check the workflow run logs (`gh run list --workflow tag-on-merge.yml --limit 1`, then `gh run view <id> --log-failed`). If you see `remote: Permission ... denied` or `protected branch hook declined`, jump to the ["Unable to push to main"](#tag-on-merge-failed-with-unable-to-push-to-main) section below.

Also verify the secrets exist:

```bash
gh secret list --repo OWNER/REPO
# Expected: CI_APP_ID and CI_APP_PRIVATE_KEY
```

And that branch protection allows the App to bypass:

```bash
gh api /repos/OWNER/REPO/branches/main/protection
# Look for the bypass_pull_request_allowances.apps array
```

---

## tag-on-merge failed with "Unable to push to main"

**Cause.** Branch protection is blocking even the GitHub App's push. A valid GitHub App token is necessary but not sufficient — the App must ALSO be explicitly listed as a bypass actor in the branch protection rule. Without the bypass entry, the protection rule rejects the push with "protected branch hook declined".

**Fix.** In Settings → Branches → Branch protection rules → `main` → Edit:

1. Enable "Require a pull request before merging" (probably already on).
2. Enable "Allow specified actors to bypass required pull requests".
3. In the search box, type the GitHub App name (e.g. `panoragrowth-ci-bot`) and select it from the dropdown.
4. Save.

Re-run `tag-on-merge.yml` by pushing a trivial empty commit to `main` via the App (or by merging another PR).

**Alternatives (not recommended).**

- Disabling branch protection entirely. Works, but you lose review enforcement. Acceptable only for personal/sandbox repos.
- Granting the GitHub App `Administration: write` permission so it can bypass any rule. Works, but dramatically widens the App's blast radius. The bypass-actor approach is strictly better — it grants exactly the privilege needed, no more.

---

## CHANGELOG.md was created but has unexpected formatting

**Cause.** Most likely a mismatch between what you expected from `changelog.mode` and what the pipe actually did.

- `changelog.mode: "last_commit"` (default): only the last commit of the merged PR appears in the CHANGELOG section for that version.
- `changelog.mode: "full"`: every commit since the previous tag appears.

A CHANGELOG that looks "too short" usually means you expected `full` mode but got the default `last_commit` mode.

**Fix.** Check your `.versioning.yml`:

```yaml
changelog:
  mode: "full"   # or "last_commit"
```

Other formatting knobs to verify:

- `changelog.use_emojis` — prepends each entry with the commit type's emoji
- `changelog.include_commit_link` — requires `changelog.commit_url` to be set
- `changelog.include_ticket_link` — requires `tickets.url` to be set
- `changelog.include_author` — toggles the author name

See [`docs/architecture/README.md`](architecture/README.md#changelog-system) for the full mode explanation, and [`scripts/defaults.yml`](../scripts/defaults.yml) for the complete list of keys.

---

## Docker image pull failed — "manifest unknown"

**Cause.** Either the image reference is wrong, or the `:latest` tag was temporarily unavailable during an image build, or the ECR Public alias transitioned while you were using `:latest`.

**Fix.**

1. Verify the URL exactly matches `public.ecr.aws/k5n8p2t3/panora-versioning-pipe:latest`. The `k5n8p2t3` alias is **AWS auto-generated** and is the current canonical alias. It will transition to `panoragrowth` once AWS approves the custom alias — during the transition, both paths will resolve to the same image, but after the transition, the old path will stop working.
2. **Pin to a specific version tag in production**: `public.ecr.aws/k5n8p2t3/panora-versioning-pipe:v0.5.5` (or whatever version you validated against). Version pins give you reproducible builds and insulate you from the alias transition. Only use `:latest` in development repos where you actively want to track the newest pipe release.
3. If you are hitting this inside the pipe's own producer repo (GHCR), the image reference is `ghcr.io/panoragrowth/panora-versioning-pipe:latest` — but that registry is for the producer's self-versioning only. Consumer repos should use ECR Public (the `architecture/docker-image-distribution` engram topic documents this dual-registry decision).

---

## Per-folder routing is not routing as expected

**Cause.** Misconfiguration in `changelog.per_folder`. The three knobs that commonly trip people up are `folders`, `scope_matching`, and `fallback`.

**Fix.** Verify each key against [`examples/configs/versioning-monorepo.yml`](../examples/configs/versioning-monorepo.yml):

- `per_folder.folders`: list of root folders that can contain subfolder CHANGELOGs (e.g. `["projects"]`). The pipe looks for subfolders inside each listed folder.
- `per_folder.folder_pattern`: regex filter on subfolder names (e.g. `"^[0-9]{3}-"` matches `001-service-api` but not `docs`).
- `per_folder.scope_matching`: `"suffix"` means a commit scope `service-api` matches folder `001-service-api` (folder name ends with scope). `"exact"` means the folder name must equal the scope exactly.
- `per_folder.fallback`: what to do with commits whose scope does not match any folder. `"root"` routes unmatched commits to the root `CHANGELOG.md`. `"file_path"` inspects the commit's modified files and tries to infer the target folder from the paths.

The routing flow is:

```
scope match → subfolder discovery → file_path fallback (if configured) → root
```

See [`docs/per-folder-changelog/README.md`](per-folder-changelog/README.md) for the full flow, edge cases, and examples.

Also remember: per-folder routing **requires `commits.format: "conventional"`**. Ticket format does not carry a scope and cannot drive folder routing.

---

## Multi-commit PR produced an unexpected bump level

**Cause.** The pipe uses **last-commit-wins** bump semantics, not highest-wins. If your merged PR has three commits — `feat: A`, `feat: B`, `fix: C` — the bump is **patch** because the last commit is a `fix:`. The earlier `feat:` commits are ignored for bump resolution (they may still appear in the CHANGELOG if `changelog.mode: "full"`, but they do not influence the version bump).

This is documented in [`docs/architecture/README.md`](architecture/README.md#version-system) under "Version system" and in the `README.md` "Bump rules" table.

**Fix 1 — use squash merge (recommended).** With a squash merge, the squash commit is the only commit that lands on `main`. Its subject is what you wrote in the PR title / merge dialog, and it determines the bump unambiguously. This is the simplest fix and aligns with the pipe's design assumptions.

**Fix 2 — reorder commits before merging.** If you must preserve the commit history, rebase the feature branch so the highest-bump commit is last. This is brittle — anyone who force-pushes or adds a "lint fix" commit later will break the assumption.

**Fix 3 — wait for highest-wins mode.** A `highest-wins` bump mode is tracked in the internal backlog (ticket 023). It is not implemented yet and there is no timeline.

---

## My config has `commit_type_overrides` but the override is ignored

**Cause.** Either a typo in the key name, or the override references a commit type that does not exist in [`scripts/defaults.yml`](../scripts/defaults.yml). `commit_type_overrides` is a patch mechanism — it updates existing types by name. It does not create new types (for that, you would replace the whole `commit_types` array, which is a much bigger operation).

**Fix.**

1. Verify the key is spelled `commit_type_overrides` (plural, with underscores). Not `commit_types_override`, not `commitTypeOverrides`.
2. Verify each overridden type name matches exactly a `name:` field in `scripts/defaults.yml`'s `commit_types` array. The built-in types are: `breaking`, `feat`, `feature`, `fix`, `hotfix`, `security`, `revert`, `perf`, `refactor`, `docs`, `test`, `chore`, `build`, `ci`, `style`.
3. If you want to override `docs` to not trigger a bump:

   ```yaml
   commit_type_overrides:
     docs:
       bump: "none"
   ```

   This is the canonical example used by the pipe itself (see [`examples/configs/versioning-conventional.yml`](../examples/configs/versioning-conventional.yml)).

4. `commit_type_overrides` is a flat map of `type_name → field_overrides`. Only the fields you set are changed; everything else inherits from the default. This was the fix for Finding #8 in the internal review log (yq replacing the full `commit_types` array on any override) — it exists specifically so you don't have to copy the whole 17-entry array just to tweak one field.

---

## My hotfix commit produced no tag — nothing happened at all

**Cause.** The `version.components.patch.enabled` flag is explicitly set to `false` in `.versioning.yml`. As of v0.6.3, `patch.enabled` is `true` by default, so this only happens when the consumer has opted out deliberately. With the opt-out, hotfix commits are a **no-op** — the pipe detects the signal, emits a 3-line INFO log explaining why nothing happened, and creates no tag.

Look for the INFO log in your CI run:

```
INFO: Hotfix commit detected ("hotfix: fix button") but version.components.patch.enabled is false.
INFO: Skipping tag creation (consumer opted out of patch component).
INFO: To enable hotfix tags, set version.components.patch.enabled: true in your .versioning.yml.
```

**Fix.** If you want hotfix tags, remove the `patch.enabled: false` line (or set it to `true`):

```yaml
version:
  components:
    patch:
      enabled: true
      initial: 0
```

The next hotfix merged to your tag branch will bump PATCH and produce a tag like `v0.5.9.1`. See [`docs/adoption-guide.md`](adoption-guide.md) Step 5 for the full hotfix workflow.

If you DO want hotfix commits to be a no-op (for example, if your repo uses a 3-component versioning scheme and hotfix is just a label without a distinct release channel), keep `patch.enabled: false` and treat the INFO log as expected behavior.

---

## My hotfix branch was merged but the scenario wasn't recognized

**Cause.** As of v0.6.3, `scripts/detection/detect-scenario.sh` in branch context (post-merge) uses **pure git** to detect a hotfix — no API calls, no platform-specific tools. It looks in two places:

1. **Primary**: the merge commit subject at HEAD starts with `{keyword}:` or `{keyword}(`, where `{keyword}` comes from `hotfix.keyword` in your `.versioning.yml` (default `"hotfix"`).
2. **Secondary (merge commit style only)**: if HEAD is a merge commit (has 2+ parents), the pipe also inspects the subject of the second parent — the tip of the branch that was merged in. This covers the traditional 3-way merge where HEAD's subject is "Merge pull request #N from ..." and the hotfix signal lives on the branch tip.

With **squash merge** (recommended), the merge commit subject is the PR title. If the PR title does not start with `hotfix:`, the primary detection misses and the pipe falls through to `development_release`.

With **rebase merge**, the last replayed commit's subject is HEAD. If the last commit on the branch is `hotfix: foo`, detection fires.

With **merge commit** style, the branch-tip subject is inspected automatically (secondary check).

**Fix.** Start the PR title with `hotfix:` — for example `hotfix: patch auth token leak`. GitHub and Bitbucket both append `(#NN)` or similar to the subject during squash merge, which does not disrupt the prefix match. The branch name itself can still be `hotfix/whatever` (and should be, for PR-context detection ergonomics), but the merge commit subject (or the branch tip subject for merge-commit style) is what survives into the post-merge detection.

If you already merged and didn't set the PR title correctly, the release is treated as a normal `development_release`. Roll the fix forward in the next regular release — there is no way to retroactively re-run the scenario detection without a new merge commit.

**Custom keyword.** If your team uses a different convention (e.g. `urgent:`, `critical:`), set `hotfix.keyword` in `.versioning.yml`. The match is a strict prefix — `hotfixed: foo` will NOT match when keyword is `hotfix`, and `urgent: foo` will NOT match when keyword is the default `hotfix`.

---

## My hotfix tag looks like `v0.5.9.1.1` or similar

**Cause.** Unexpected parsing artifact — this shouldn't happen in normal use. The most likely explanation is manual tag creation that didn't round-trip through `parse_version_components` + `build_version_string`.

**Fix.** File a bug against `panora-versioning-pipe` with:

1. The output of `gh release list --limit 5` (or the equivalent tag listing).
2. Your `.versioning.yml` contents.
3. The commit subject that triggered the bad tag.
4. The `calculate-version.sh` log from the failing tag-on-merge run.

The pipe's unit tests (`tests/unit/versioning/patch-component.bats` and `hotfix-bump.bats`) lock the expected format — a failure at runtime would indicate a regression the tests didn't catch.
