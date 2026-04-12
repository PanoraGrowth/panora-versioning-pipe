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

# Load common functions and config
. "${AUTOMATIONS_DIR}/lib/common.sh"
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
        log_section "PR PIPELINE SKIPPED"
        log_info "Target branch: $TARGET_BRANCH"
        echo ""
        log_info "PR pipelines only run for PRs targeting:"
        log_info "  - $DEV_BRANCH (development releases)"
        log_info "  - $PREPROD_BRANCH (hotfixes)"
        log_info "  - $PROD_BRANCH (hotfixes)"
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
# EXECUTE SCENARIO
# ============================================================================
case "$SCENARIO" in
    development_release|hotfix)
        echo ""
        log_section "PR PIPELINE — ${SCENARIO}"
        echo ""

        # Validate commits
        "${AUTOMATIONS_DIR}/validation/validate-commits.sh"

        echo ""
        log_section "PIPELINE COMPLETED SUCCESSFULLY"
        ;;

    promotion_to_preprod|promotion_to_main)
        echo ""
        log_section "PROMOTION — NO ACTION NEEDED"
        log_info "This is a promotion PR from one environment to another."
        log_info "No changelog or version changes are made during promotions."
        ;;

    *)
        echo ""
        log_section "UNKNOWN SCENARIO — NO ACTION"
        log_info "This PR scenario is not recognized."
        log_info "No pipeline action needed."
        ;;
esac
