#!/bin/sh
# ============================================================================
# Script: pr-pipeline.sh
# Description: Main orchestrator for PR pipeline
# Inputs: VERSIONING_PR_ID, VERSIONING_BRANCH, VERSIONING_TARGET_BRANCH, VERSIONING_COMMIT
# Outputs: Complete PR pipeline execution
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AUTOMATIONS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load config parser to get branch names
. "${AUTOMATIONS_DIR}/lib/config-parser.sh"

# Get branch names from config
DEV_BRANCH=$(get_development_branch)
PREPROD_BRANCH=$(get_preprod_branch)
PROD_BRANCH=$(get_production_branch)

# ============================================================================
# EARLY EXIT: Only run for PRs targeting development, pre-production, or main
# ============================================================================
TARGET_BRANCH="${VERSIONING_TARGET_BRANCH}"

case "$TARGET_BRANCH" in
    "$DEV_BRANCH"|"$PREPROD_BRANCH"|"$PROD_BRANCH")
        # Continue with pipeline
        ;;
    *)
        echo "=========================================="
        echo "  PR PIPELINE SKIPPED"
        echo "=========================================="
        echo "Target branch: $TARGET_BRANCH"
        echo ""
        echo "PR pipelines only run for PRs targeting:"
        echo "  - $DEV_BRANCH (development releases)"
        echo "  - $PREPROD_BRANCH (hotfixes)"
        echo "  - $PROD_BRANCH (hotfixes)"
        echo "=========================================="
        exit 0
        ;;
esac

# ============================================================================
# SCENARIO DETECTION
# ============================================================================
"${AUTOMATIONS_DIR}/detection/detect-scenario.sh"

# Load scenario for routing
. /tmp/scenario.env

# ============================================================================
# SCENARIO 1: Development Release
# ============================================================================
if [ "$SCENARIO" = "development_release" ]; then
    echo ""
    echo "=========================================="
    echo "  DEVELOPMENT RELEASE PIPELINE"
    echo "=========================================="
    echo ""

    # Step 1: Validate commits
    "${AUTOMATIONS_DIR}/validation/validate-commits.sh"

    echo ""

    # Step 2: Calculate next version with timestamp
    "${AUTOMATIONS_DIR}/versioning/calculate-version.sh"

    echo ""

    # Step 3: Write version to file(s) if configured
    "${AUTOMATIONS_DIR}/versioning/write-version-file.sh"

    echo ""

    # Step 4: Generate CHANGELOG (last commit only)
    "${AUTOMATIONS_DIR}/changelog/generate-changelog-last-commit.sh"

    echo ""

    # Step 4b: Generate per-folder CHANGELOGs (if enabled)
    "${AUTOMATIONS_DIR}/changelog/generate-changelog-per-folder.sh"

    echo ""

    # Step 5: Commit and push CHANGELOG + version files
    "${AUTOMATIONS_DIR}/changelog/update-changelog.sh"

    echo ""
    echo "=========================================="
    echo "  PIPELINE COMPLETED SUCCESSFULLY"
    echo "=========================================="
fi

# ============================================================================
# SCENARIO 2: Hotfix to Main (Production)
# ============================================================================
if [ "$SCENARIO" = "hotfix_to_main" ]; then
    echo ""
    echo "=========================================="
    echo "  HOTFIX TO PRODUCTION PIPELINE"
    echo "=========================================="
    echo ""

    # Step 1: Validate commits
    "${AUTOMATIONS_DIR}/validation/validate-commits.sh"

    echo ""

    # Step 2: Generate hotfix CHANGELOG entry
    "${AUTOMATIONS_DIR}/changelog/generate-hotfix-changelog.sh"

    echo ""

    # Step 3: Commit and push CHANGELOG
    "${AUTOMATIONS_DIR}/changelog/update-changelog.sh"

    echo ""
    echo "=========================================="
    echo "  HOTFIX PIPELINE COMPLETED SUCCESSFULLY"
    echo "=========================================="
fi

# ============================================================================
# SCENARIO 3: Hotfix to Pre-production
# ============================================================================
if [ "$SCENARIO" = "hotfix_to_preprod" ]; then
    echo ""
    echo "=========================================="
    echo "  HOTFIX TO PRE-PRODUCTION PIPELINE"
    echo "=========================================="
    echo ""

    # Step 1: Validate commits
    "${AUTOMATIONS_DIR}/validation/validate-commits.sh"

    echo ""

    # Step 2: Generate hotfix CHANGELOG entry
    "${AUTOMATIONS_DIR}/changelog/generate-hotfix-changelog.sh"

    echo ""

    # Step 3: Commit and push CHANGELOG
    "${AUTOMATIONS_DIR}/changelog/update-changelog.sh"

    echo ""
    echo "=========================================="
    echo "  HOTFIX PIPELINE COMPLETED SUCCESSFULLY"
    echo "=========================================="
fi

# ============================================================================
# SCENARIO 4: Promotions (No action needed)
# ============================================================================
if [ "$SCENARIO" = "promotion_to_preprod" ] || [ "$SCENARIO" = "promotion_to_main" ]; then
    echo ""
    echo "=========================================="
    echo "  PROMOTION - NO ACTION NEEDED"
    echo "=========================================="
    echo "This is a promotion PR from one environment to another."
    echo "No changelog or version changes are made during promotions."
    echo "=========================================="
fi

# ============================================================================
# SCENARIO 5: Unknown
# ============================================================================
if [ "$SCENARIO" = "unknown" ]; then
    echo ""
    echo "=========================================="
    echo "  UNKNOWN SCENARIO - NO ACTION"
    echo "=========================================="
    echo "This PR scenario is not recognized."
    echo "No pipeline action needed."
    echo "=========================================="
fi
