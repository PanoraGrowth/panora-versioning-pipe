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

# Set git identity for commits (configurable via environment variables)
GIT_USER_NAME="${GIT_USER_NAME:-"CI Pipeline"}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-"ci@panora-versioning-pipe.noreply"}"

git config --global user.name "$GIT_USER_NAME"
git config --global user.email "$GIT_USER_EMAIL"

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
