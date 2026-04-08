#!/bin/bash
# ------------------------------------------------------------------------------
# pipe.sh
#
# Entry point for the Versioning Pipe. Runs inside the Docker container and
# decides which pipeline to execute based on context (PR or branch push).
#
# Required environment variables:
#   VERSIONING_BRANCH         - Current branch name
#   VERSIONING_PR_ID          - Pull request ID (set only when running in PR context)
#   VERSIONING_TARGET_BRANCH  - PR target/destination branch (required for PR pipeline)
#   VERSIONING_COMMIT         - Current commit SHA (used for tags and reporting)
# ------------------------------------------------------------------------------

set -e

SCRIPTS_DIR="/pipe"

# Mark workspace as safe (required when running as Docker action with different user)
git config --global --add safe.directory "$(pwd)" 2>/dev/null || true

# Configure git identity and fetch refs
"${SCRIPTS_DIR}/setup/configure-git.sh"

# =============================================================================
# Platform auto-detection
# Auto-map platform-specific variables to VERSIONING_* when not already set.
# Explicit VERSIONING_* vars always take priority (allows manual override).
# =============================================================================

if [ -n "${BITBUCKET_BUILD_NUMBER:-}" ]; then
    # Bitbucket Pipelines
    echo "Platform detected: Bitbucket Pipelines"
    export VERSIONING_PR_ID="${VERSIONING_PR_ID:-${BITBUCKET_PR_ID:-}}"
    export VERSIONING_BRANCH="${VERSIONING_BRANCH:-${BITBUCKET_BRANCH:-}}"
    export VERSIONING_TARGET_BRANCH="${VERSIONING_TARGET_BRANCH:-${BITBUCKET_PR_DESTINATION_BRANCH:-}}"
    export VERSIONING_COMMIT="${VERSIONING_COMMIT:-${BITBUCKET_COMMIT:-}}"

elif [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    # GitHub Actions
    echo "Platform detected: GitHub Actions"
    if [ "${GITHUB_EVENT_NAME:-}" = "pull_request" ]; then
        # PR event: read PR number from event payload
        if [ -n "${GITHUB_EVENT_PATH:-}" ] && [ -f "${GITHUB_EVENT_PATH}" ]; then
            _GH_PR_ID=$(jq -r '.pull_request.number // empty' "$GITHUB_EVENT_PATH" 2>/dev/null || echo "")
        fi
        export VERSIONING_PR_ID="${VERSIONING_PR_ID:-${_GH_PR_ID:-}}"
        export VERSIONING_BRANCH="${VERSIONING_BRANCH:-${GITHUB_HEAD_REF:-}}"
        export VERSIONING_TARGET_BRANCH="${VERSIONING_TARGET_BRANCH:-${GITHUB_BASE_REF:-}}"
    else
        # Push event
        export VERSIONING_BRANCH="${VERSIONING_BRANCH:-${GITHUB_REF_NAME:-}}"
    fi
    export VERSIONING_COMMIT="${VERSIONING_COMMIT:-${GITHUB_SHA:-}}"

else
    echo "Platform detected: Generic CI (using VERSIONING_* variables)"
fi

# Validate required variables
if [ -z "${VERSIONING_BRANCH:-}" ] && [ -z "${VERSIONING_PR_ID:-}" ]; then
    echo "ERROR: Cannot determine pipeline type"
    echo ""
    echo "No CI platform detected and no VERSIONING_* variables set."
    echo "Set VERSIONING_PR_ID (for PR pipeline) or VERSIONING_BRANCH (for branch pipeline)."
    echo ""
    echo "Supported platforms (auto-detected):"
    echo "  - Bitbucket Pipelines"
    echo "  - GitHub Actions"
    echo ""
    echo "For other CI systems, set these environment variables manually:"
    echo "  VERSIONING_BRANCH        - Current branch name"
    echo "  VERSIONING_PR_ID         - Pull request ID (PR pipeline only)"
    echo "  VERSIONING_TARGET_BRANCH - PR target branch (PR pipeline only)"
    echo "  VERSIONING_COMMIT        - Current commit SHA"
    exit 1
fi

# Detect pipeline type
if [ -n "${VERSIONING_PR_ID:-}" ]; then
    echo "=========================================="
    echo "  VERSIONING PIPE - PR PIPELINE"
    echo "=========================================="
    echo ""

    # Run the PR pipeline (validation, changelog, etc.)
    "${SCRIPTS_DIR}/orchestration/pr-pipeline.sh"

elif [ -n "${VERSIONING_BRANCH:-}" ]; then
    echo "=========================================="
    echo "  VERSIONING PIPE - BRANCH PIPELINE"
    echo "=========================================="
    echo ""

    # Run the branch pipeline (tag creation)
    "${SCRIPTS_DIR}/orchestration/branch-pipeline.sh"

fi

echo ""
echo "=========================================="
echo "  VERSIONING PIPE COMPLETED"
echo "=========================================="
# Trigger image rebuild
