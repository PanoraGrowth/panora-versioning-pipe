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

# Validate required variables
if [ -z "${VERSIONING_BRANCH:-}" ] && [ -z "${VERSIONING_PR_ID:-}" ]; then
    echo "ERROR: Cannot determine pipeline type"
    echo "Set VERSIONING_PR_ID (for PR pipeline) or VERSIONING_BRANCH (for branch pipeline)"
    echo ""
    echo "Example mappings:"
    echo "  Bitbucket: VERSIONING_BRANCH=\$BITBUCKET_BRANCH"
    echo "  GitHub:    VERSIONING_BRANCH=\$GITHUB_HEAD_REF"
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
