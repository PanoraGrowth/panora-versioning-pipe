# GitHub App Setup

**Last updated:** 2026-04-10 (v0.5.5)

This guide walks through creating a GitHub App, installing it on a consumer repository, generating its private key, and wiring both secrets into the `tag-on-merge` workflow. It is the single hardest prerequisite for adopting `panora-versioning-pipe`, and the only prerequisite that cannot be automated from a template.

---

## Why a GitHub App is required

The `tag-on-merge.yml` workflow needs to push a CHANGELOG commit and a new version tag back to `main`. The default `GITHUB_TOKEN` provided by GitHub Actions cannot do this in two ways:

1. It cannot push to a `main` branch protected against direct pushes by `GITHUB_TOKEN` (branch protection rules reject it).
2. It cannot re-trigger downstream workflows from its own pushes — an intentional GitHub Actions safety feature designed to prevent infinite loops.

A short-lived GitHub App installation token solves both: it bypasses the `GITHUB_TOKEN` branch-protection class, and pushes authored by a GitHub App installation DO re-trigger downstream workflows (which is what you want for, say, a downstream `publish.yml` that runs on `workflow_run` after a tag is created). This is documented as a hard requirement in the pipe's internal notes (`requirements/github-app-token` in the engram memory store) and is the most common adoption blocker for new consumer repos.

The PR workflow (`pr-versioning.yml`) does NOT need the GitHub App token — the default `GITHUB_TOKEN` with `contents: write` is sufficient because it only pushes to the PR's feature branch, not to `main`.

---

## Decision: org-wide or per-repo App?

| | Org-wide App | Per-repo App |
|-|---|---|
| **Pros** | One App for all consumer repos. Install on each repo individually. Private key rotation propagates to every repo. | Smallest blast radius — the App can only ever touch one repo. |
| **Cons** | Larger blast radius if the private key leaks (can touch every installed repo). | N App creations, N private keys, N rotations. Operationally painful at scale. |
| **When to pick it** | You have (or will have) more than 2–3 consumer repos. Recommended default. | You have a single high-sensitivity repo and one-off compliance concerns. |

For most teams, create **one org-wide GitHub App** and install it on each consumer repo as adoption rolls out.

---

## Step 1 — Create the GitHub App

1. Navigate to the App creation page:
   - **Organization App** (recommended): `https://github.com/organizations/YOUR_ORG/settings/apps/new`
   - **User App** (for personal / solo use): Settings → Developer settings → GitHub Apps → New GitHub App
2. Fill in the form:
   - **GitHub App name**: `panoragrowth-ci-bot` (or similar — must be globally unique across GitHub).
   - **Homepage URL**: any valid URL. Your organization website is fine.
   - **Webhook**: **uncheck "Active"**. This App does not need webhooks — it is used purely as a token source.
   - **Repository permissions**:
     - `Contents`: **Read and write** (required — the pipe pushes CHANGELOG commits and tags)
     - `Metadata`: Read-only (added automatically as a dependency)
     - `Pull requests`: Read and write (optional — enables commenting on PRs if you extend the pipe later)
   - **Organization permissions**: none needed
   - **Where can this GitHub App be installed?**: **Only on this account** (locks the App to your org/user)
3. Click **Create GitHub App**.

After creation, note the **App ID** shown at the top of the settings page (a 6–8 digit number). You will need this in Step 4.

---

## Step 2 — Install the App on the target repo

1. From the App settings page, click **Install App** in the left sidebar.
2. Choose your account/org.
3. Select **Only select repositories** and pick the consumer repo(s) you want the pipe to version (e.g. `it-services-site`).
4. Click **Install**.

You can come back to this page later (Settings → Developer settings → GitHub Apps → Your App → Install App) to add more repos as adoption rolls out.

---

## Step 3 — Generate a private key

1. From the App settings page (Settings → Developer settings → GitHub Apps → Your App → General), scroll to the **Private keys** section.
2. Click **Generate a private key**.
3. A `.pem` file is downloaded automatically. **This is the only time you can download this key** — if you lose it, you must generate a new one and update every repo that references it.
4. Save the `.pem` somewhere secure temporarily (a password manager, a secret vault) — you will paste its contents into a GitHub secret in the next step, then you can delete the local file.

---

## Step 4 — Store the secrets

You now have two values:

- The **App ID** (numeric, from Step 1)
- The **private key** (PEM contents from Step 3 — including the `-----BEGIN RSA PRIVATE KEY-----` and `-----END RSA PRIVATE KEY-----` lines)

Add them as repository secrets on the target repo (Settings → Secrets and variables → Actions → New repository secret). Or, if you're rolling the App out across multiple repos in the same org, add them as **organization secrets** once and grant access to each repo individually.

| Secret name | Value |
|-------------|-------|
| `CI_APP_ID` | The numeric App ID |
| `CI_APP_PRIVATE_KEY` | The full PEM contents, including header and footer lines |

Both names are hardcoded in [`examples/github-actions/tag-on-merge.yml`](../examples/github-actions/tag-on-merge.yml) — do not rename them unless you also edit that workflow.

---

## Step 5 — Verify

Run these commands from a terminal with `gh` authenticated for the target repo:

```bash
# Both secrets should be listed
gh secret list --repo OWNER/REPO

# Returns the App installation metadata if the App is installed on this repo
gh api /repos/OWNER/REPO/installation
```

If `gh api /repos/.../installation` returns `404 Not Found`, the App was created but not installed on this repo — go back to Step 2.

If `gh secret list` shows only one of the two secrets, the second one was not saved correctly — go back to Step 4.

---

## Rotation procedure

Rotate the private key **immediately** if it is leaked, committed accidentally, or if a person who had access leaves the team.

1. Generate a new private key from the App settings page (Step 3). **The App ID does not change** — you only rotate the key, not the App itself.
2. Update the `CI_APP_PRIVATE_KEY` secret on every repo where the App is installed (or the org secret, if you used one).
3. **Revoke the old key** from the App settings page (scroll to the Private keys section — each key has a "Delete" button next to it).
4. Verify the next `tag-on-merge` run succeeds with the new key.

A leaked `CI_APP_ID` alone is NOT a security incident — the App ID is not a secret, it is just a numeric identifier. Only the private key is sensitive.

---

## Security considerations

- **The installation token is short-lived.** `actions/create-github-app-token@v1` generates a token scoped to the installation with a 1-hour default lifetime. It is masked in Actions logs and expires whether or not the job succeeds.
- **The App can only access repos where it is installed.** Even with a valid private key and App ID, an attacker cannot read repos the App was never installed on.
- **Never commit the private key to any repo.** Not to the consumer repo, not to a "private" repo, not to a gist. GitHub's secret scanning detects `-----BEGIN RSA PRIVATE KEY-----` patterns and will alert on leaks, but the alert is reactive — by the time it fires, the key is already public.
- **Do not pass the token between jobs.** The canonical workflow generates the token, uses it for checkout, and passes it to the pipe container **inline, in a single job**. Passing it through `outputs:` between jobs exposes it in the Actions UI. The pipe's own [`tag-on-merge.yml`](../.github/workflows/tag-on-merge.yml) follows this pattern — mirror it in your consumer repo.
- **The App does NOT need admin permissions.** If someone suggests granting `Administration: write` to "fix" branch protection issues, push back — the right fix is to add the App as a bypass actor in branch protection settings, not to give it admin. See [`troubleshooting.md`](troubleshooting.md#tag-on-merge-failed-with-unable-to-push-to-main).
