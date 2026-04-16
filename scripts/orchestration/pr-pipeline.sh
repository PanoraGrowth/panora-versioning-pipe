#!/bin/sh
# shellcheck shell=ash
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
# shellcheck source=../lib/common.sh
. "${AUTOMATIONS_DIR}/lib/common.sh"
# shellcheck source=../lib/config-parser.sh
. "${AUTOMATIONS_DIR}/lib/config-parser.sh"

# Get branch config from config
TAG_BRANCH=$(get_tag_branch)

# ============================================================================
# EARLY EXIT: Only run for PRs targeting tag_on or any hotfix_target branch
# ============================================================================
TARGET_BRANCH="${VERSIONING_TARGET_BRANCH}"

if [ "$TARGET_BRANCH" = "$TAG_BRANCH" ] || is_hotfix_target "$TARGET_BRANCH"; then
    : # Continue with pipeline
else
    log_section "PR PIPELINE SKIPPED"
    log_info "Target branch: $TARGET_BRANCH"
    echo ""
    log_info "PR pipelines only run for PRs targeting:"
    log_info "  - $TAG_BRANCH (tag branch)"
    log_info "  - configured hotfix_targets ($(get_hotfix_targets | tr ' ' ', '))"
    exit 0
fi

# ============================================================================
# SCENARIO DETECTION
# ============================================================================
"${AUTOMATIONS_DIR}/detection/detect-scenario.sh"

# Load scenario for routing
# shellcheck disable=SC1091
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
