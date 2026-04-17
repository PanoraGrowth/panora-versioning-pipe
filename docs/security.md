# Security Model

This document outlines the security model of panora-versioning-pipe, covering authentication, authorization, credential management, and consumer security invariants.

## Why a GitHub App Token?

The pipe uses a GitHub App installation token (not a Personal Access Token) for the following reasons:

1. **Scoped permissions** — GitHub App tokens are restricted to the minimum required permissions (Contents: Read & write, Metadata: Read-only). Personal Access Tokens (classic) are account-wide and cannot be fine-grained.

2. **Short-lived tokens** — The `actions/create-github-app-token` action generates tokens that expire in approximately 1 hour. This dramatically reduces the blast radius if a token is leaked.

3. **Installation-scoped** — A GitHub App token only works for the specific repositories where the app is installed. A stolen token cannot access other organizations' repositories.

4. **Audit trail** — GitHub App activity is logged separately from user activity, making it easier to detect misuse or compromise.

5. **No account takeover** — A leaked GitHub App token cannot be used to authenticate as a human account, steal SSH keys, or access private account settings.

6. **Automatic rotation** — The token is generated fresh on each workflow run. There is no long-lived secret to rotate manually.

## `CI_APP_PRIVATE_KEY` Rotation Runbook

The private key for the GitHub App must be kept secure and rotated periodically. Follow this runbook for both routine rotation and suspected compromise scenarios.

### Prerequisites

- Admin access to the GitHub App (Settings → Developer settings → GitHub Apps)
- Admin access to the consumer repository (Settings → Secrets and variables → Actions)
- Read-only access to `git log` and repository history

### Routine rotation (every 6-12 months)

1. **Generate a new private key**
   - Go to Settings → Developer settings → GitHub Apps → [Your App]
   - Scroll to "Private keys"
   - Click "Generate a private key"
   - Download the new PEM file immediately (GitHub does not store it)

2. **Store the new key securely**
   - If using a secrets manager (recommended), add the new key with a timestamp suffix (e.g., `CI_APP_PRIVATE_KEY_2026_04`)
   - Do NOT commit the PEM file to the repository
   - Do NOT add it to email or chat — transfer via your organization's secure credential management system

3. **Update the workflow secret**
   - Go to the consumer repository
   - Settings → Secrets and variables → Actions
   - Update `CI_APP_PRIVATE_KEY` with the new key contents
   - Verify the update by reviewing the secret's last modified timestamp

4. **Delete the old private key from GitHub**
   - Return to Settings → Developer settings → GitHub Apps → [Your App]
   - Scroll to "Private keys"
   - Click the trash icon next to the old key
   - Confirm deletion

5. **Verify rotation in the next release**
   - Merge a change to `main` and wait for the `tag-on-merge.yml` workflow to run
   - Confirm that the workflow succeeds
   - Check the Git log: `git log --oneline | head -5` should show the new tag created by the pipe

### Suspected compromise (immediate action required)

If the private key is suspected to be leaked or exposed (e.g., logged in plaintext, committed to a repository, shared in an unencrypted channel):

1. **Immediately delete the compromised key from GitHub**
   - Go to Settings → Developer settings → GitHub Apps → [Your App]
   - Scroll to "Private keys"
   - Click the trash icon next to the exposed key
   - Confirm deletion immediately

2. **Generate a new private key**
   - Click "Generate a private key"
   - Download the new PEM file

3. **Update all secrets that reference the old key**
   - For each consumer repository: Settings → Secrets and variables → Actions
   - Update `CI_APP_PRIVATE_KEY` with the new key contents
   - If multiple repositories use the same App, update all of them

4. **Review recent push activity**
   - Check `git log` in affected repositories for unexpected CHANGELOG commits or tags
   - Look for commits authored by the App user (default: "<App name>[bot]")
   - If unauthorized commits are found, force-reset the branch and notify the team

5. **Audit the App's install history** (if available in your GitHub Enterprise settings)
   - Review which repositories have the App installed
   - Verify that the install list matches expectations
   - Consider uninstalling the App from repositories that no longer need it

6. **Optional: Rotate the entire App** (highest-security option)
   - Create a new GitHub App with the same configuration
   - Install it on all consumer repositories
   - Update `CI_APP_ID` and `CI_APP_PRIVATE_KEY` in each repository
   - Uninstall the old App
   - This ensures the old key cannot be used even if recovery is incomplete

## Audit Commands for Bot User Commits

After rotation or in case of suspected compromise, use these commands to audit commits created by the GitHub App bot user:

```bash
# Find all commits authored by the App bot
git log --all --format="%H %an <%ae> %s" | grep "\[bot\]"

# Count commits by the App bot in the last 30 days
git log --all --since="30 days ago" --format="%an" | grep "\[bot\]" | wc -l

# Find commits authored by the App bot that modified sensitive files
git log --all --format="%H %an %s" --follow -- Makefile .github/workflows | grep "\[bot\]"

# Review the full diff of a suspicious commit
git show <commit-hash>

# Find all tags created by the App bot
git log --all --format="%d %an %s" | grep "tag:" | grep "\[bot\]"
```

## Consumer Security Invariants

Every consumer repository integrating the pipe must maintain these six security invariants:

### 1. Protected main branch

- Require at least one code review approval before merging to `main`
- Require status checks to pass (the `pr-versioning.yml` check must succeed)
- Dismiss stale pull request approvals when new commits are pushed
- Restrict push access to `main` — only the CI/CD system (the GitHub App) should be able to push directly

**Why**: Prevents unauthorized version tags, CHANGELOG commits, and arbitrary code from reaching production.

### 2. GitHub App token scoped to required permissions only

- The GitHub App should have **Repository → Contents: Read & write** and **Repository → Metadata: Read-only**
- Do NOT grant the App access to Secrets, Workflows, or Administration
- Do NOT grant broad organization-level permissions

**Why**: Limits the blast radius if the token is compromised. A Contents token cannot modify workflows or organization settings.

### 3. CI_APP_PRIVATE_KEY stored as an organization-level secret or equivalent

- Store the private key as a **secret** (not a variable) in the repository or organization
- Restrict read access to the secret to the GitHub Actions workflow only
- Audit secret access in Settings → Secrets and variables → Actions

**Why**: Secrets are masked in logs and have audit trails. Regular variables are logged in plaintext.

### 4. Workflow file integrity (pr-versioning.yml and tag-on-merge.yml)

- Do NOT modify the `uses:` or `run:` directives in the provided workflow files without justification
- Do NOT pass additional environment variables to the pipe container unless documented in the README
- Pin the pipe container image to a specific tag (`:v0.9.1`) rather than `:latest` or `:v0`

**Why**: Prevents tampering with the pipe's execution environment and ensures predictable behavior.

### 5. Commit format validation enforced

- Configure `commits.format` to either `"ticket"` or `"conventional"` in `.versioning.yml`
- If using `"conventional"`, enforce this in pre-commit hooks or branch protection rules
- Set `validation.require_commit_types: true` to ensure every commit follows the schema

**Why**: Prevents arbitrary commits from being merged to `main`, which could obscure the real version bump intent.

### 6. Version tags never force-pushed

- Disable `--force-push` permissions for the pipe container and human operators on the `main` branch
- If a version tag is created in error, do NOT force-push it; instead, create a new tag with the next version
- Use `git tag -d <tag>` to delete a local tag and `git push origin --delete <tag>` to delete a remote tag, then re-run the pipe

**Why**: Prevents audit-trail corruption. A force-pushed tag can hide security events or unintended changes.

## Consumer Onboarding Security Checklist

When integrating the pipe into a new consumer repository, verify every item before going to production:

- [ ] Repository has a protected `main` branch with:
  - [ ] At least one code review approval required
  - [ ] Status checks enforced (`pr-versioning.yml` must pass)
  - [ ] Stale approval dismissal enabled
  - [ ] Push access restricted (only GitHub App can push directly to `main`)

- [ ] GitHub App is installed and configured:
  - [ ] App ID is stored in `CI_APP_ID` secret
  - [ ] Private key is stored in `CI_APP_PRIVATE_KEY` secret
  - [ ] App has "Contents: Read & write" and "Metadata: Read-only" permissions only

- [ ] Workflow files are in place:
  - [ ] `.github/workflows/pr-versioning.yml` is committed and unchanged
  - [ ] `.github/workflows/tag-on-merge.yml` is committed and unchanged
  - [ ] Organization variable `VERSIONING_PIPE_TAG` is set (if using org-wide versioning)

- [ ] Versioning configuration is established:
  - [ ] `.versioning.yml` exists in repository root
  - [ ] `commits.format` is set to `"ticket"` or `"conventional"`
  - [ ] `validation.require_commit_types: true` is set
  - [ ] Commit format matches the team's workflow (conventional commits or ticket prefix)

- [ ] First release validated:
  - [ ] Create a test PR with a single commit (e.g., `feat: test commit`)
  - [ ] Verify that `pr-versioning.yml` validates the commit and generates a preview CHANGELOG
  - [ ] Merge the PR and wait for `tag-on-merge.yml` to create a version tag
  - [ ] Verify the tag matches the expected format (e.g., `v0.1.0` or `0.1.20260417143022`)
  - [ ] Audit the CHANGELOG.md commit: `git log --oneline | head -1` should show a `chore(release)` commit

- [ ] Ongoing security practices established:
  - [ ] Private key rotation schedule documented (every 6-12 months)
  - [ ] Suspected-compromise runbook shared with the team
  - [ ] Audit commands bookmarked for quarterly reviews
  - [ ] Team understands that version tags are immutable and cannot be deleted once pushed to `main`
