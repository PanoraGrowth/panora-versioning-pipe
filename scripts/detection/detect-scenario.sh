#!/bin/sh
# ------------------------------------------------------------------------------
# detect-scenario.sh
#
# Detects the pipeline scenario based on source and target branches of the PR.
# Determines which actions to take: generate changelog, create tag, etc.
# ------------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/../lib/common.sh"
. "${SCRIPT_DIR}/../lib/config-parser.sh"

log_section "DETECTING PIPELINE SCENARIO"

SOURCE_BRANCH="${VERSIONING_BRANCH}"
TARGET_BRANCH="${VERSIONING_TARGET_BRANCH}"

log_info "Source Branch: $SOURCE_BRANCH"
log_info "Target Branch: $TARGET_BRANCH"
echo ""

# Get branch names from config
DEV_BRANCH=$(get_development_branch)
PREPROD_BRANCH=$(get_preprod_branch)
PROD_BRANCH=$(get_production_branch)
HOTFIX_PREFIX=$(get_hotfix_branch_prefix)

# Detect scenario based on target branch
case "$TARGET_BRANCH" in
    "$DEV_BRANCH")
        # Any branch targeting development = development release
        SCENARIO="development_release"
        echo "Scenario: Development Release (Changelog + Tag)"
        ;;

    "$PREPROD_BRANCH")
        # Check if it is a hotfix or a promotion
        case "$SOURCE_BRANCH" in
            ${HOTFIX_PREFIX}*)
                SCENARIO="hotfix_to_preprod"
                echo "Scenario: Hotfix to Pre-production (Changelog, no Tag)"
                ;;
            "$DEV_BRANCH")
                SCENARIO="promotion_to_preprod"
                echo "Scenario: Promotion to Pre-production (No action)"
                ;;
            *)
                SCENARIO="unknown"
                echo "Scenario: Unknown - No pipeline action"
                ;;
        esac
        ;;

    "$PROD_BRANCH")
        # Production: can be hotfix, promotion, or direct feature to main
        case "$SOURCE_BRANCH" in
            ${HOTFIX_PREFIX}*)
                SCENARIO="hotfix_to_main"
                echo "Scenario: Hotfix to Production (Changelog, no Tag)"
                ;;
            "$PREPROD_BRANCH")
                SCENARIO="promotion_to_main"
                echo "Scenario: Promotion to Production (No action)"
                ;;
            *)
                # Direct-to-main workflow
                SCENARIO="development_release"
                echo "Scenario: Direct to Main Release (Changelog + Tag)"
                ;;
        esac
        ;;

    *)
        SCENARIO="unknown"
        echo "Scenario: Unknown - No pipeline action"
        ;;
esac

# Save scenario for other scripts to read
echo "SCENARIO=$SCENARIO" > /tmp/scenario.env
echo ""
