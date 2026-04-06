#!/bin/sh
# ============================================================================
# Script: configure-git.sh
# Description: Configure git for pipeline operations
# Inputs: VERSIONING_TARGET_BRANCH (env, optional)
#         GIT_USER_NAME (env, optional, default: "CI Pipeline")
#         GIT_USER_EMAIL (env, optional, default: "ci@panora-versioning-pipe.noreply")
# Outputs: Configured git, fetched refs and tags
# ============================================================================

set -e

echo "Configuring git..."

# Mark workspace as safe (required when running in Docker with different user)
git config --global --add safe.directory "$(pwd)"

# Set git identity for commits (configurable via environment variables)
GIT_USER_NAME="${GIT_USER_NAME:-"CI Pipeline"}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-"ci@panora-versioning-pipe.noreply"}"

git config --global user.name "$GIT_USER_NAME"
git config --global user.email "$GIT_USER_EMAIL"

# Configure service account credentials for pushing to protected branches
# GitHub: CI_GITHUB_TOKEN from GitHub App (passed via workflow env)
# Bitbucket: CI_BOT_USERNAME + CI_BOT_APP_PASSWORD (pipeline variables)
if [ -n "${CI_GITHUB_TOKEN:-}" ]; then
    echo "Configuring GitHub App token for push access..."
    CURRENT_URL=$(git remote get-url origin 2>/dev/null || echo "")
    REPO_PATH=$(echo "$CURRENT_URL" | sed -E 's|\.git$||' | sed -E 's|.*github.com[:/]||')
    if [ -n "$REPO_PATH" ]; then
        git remote set-url origin "https://x-access-token:${CI_GITHUB_TOKEN}@github.com/${REPO_PATH}.git"
        echo "GitHub App token configured for push access"
    fi
elif [ -n "${CI_BOT_USERNAME:-}" ] && [ -n "${CI_BOT_APP_PASSWORD:-}" ]; then
    echo "Configuring Bitbucket service account for push access..."
    CURRENT_URL=$(git remote get-url origin 2>/dev/null || echo "")
    if echo "$CURRENT_URL" | grep -q "bitbucket.org"; then
        REPO_PATH=$(echo "$CURRENT_URL" | sed -E 's|.*bitbucket.org[:/](.*)\.git$|\1|' | sed 's|.*bitbucket.org[:/]||')
        git remote set-url origin "https://${CI_BOT_USERNAME}:${CI_BOT_APP_PASSWORD}@bitbucket.org/${REPO_PATH}.git"
        echo "Bitbucket service account configured for push access"
    fi
fi

# Fetch full history and tags
echo "Fetching git refs..."
git fetch --unshallow 2>/dev/null || true
git fetch --tags --force

# Fetch destination branch if in PR context
if [ -n "${VERSIONING_TARGET_BRANCH:-}" ]; then
    echo "Fetching destination branch: ${VERSIONING_TARGET_BRANCH}"
    git fetch origin "${VERSIONING_TARGET_BRANCH}:${VERSIONING_TARGET_BRANCH}"
fi

echo "Git configured successfully"
