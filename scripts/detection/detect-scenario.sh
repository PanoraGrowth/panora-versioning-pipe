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
COMMIT="${VERSIONING_COMMIT:-HEAD}"

log_info "Source Branch: $SOURCE_BRANCH"
log_info "Target Branch: ${TARGET_BRANCH:-<branch context>}"
echo ""

# Get branch names from config
DEV_BRANCH=$(get_development_branch)
PREPROD_BRANCH=$(get_preprod_branch)
PROD_BRANCH=$(get_production_branch)
HOTFIX_PREFIX=$(get_hotfix_branch_prefix)

# ----------------------------------------------------------------------------
# Branch context (no PR target): called by branch-pipeline.sh on the tag
# branch after a merge. A PR's source branch is no longer observable from the
# merge commit alone (squash merges drop it), so hotfix detection uses two
# strategies in order:
#   1. Commit type convention — fast, local, platform-agnostic. The merge
#      commit subject must start with `hotfix:` or `hotfix(...)` (both the
#      ticket-based bare form and the conventional/scoped form).
#   2. GitHub API PR lookup — fallback when the subject does not carry the
#      signal (e.g. a merge commit on main from a hotfix branch). Requires gh,
#      authentication, and GITHUB_REPOSITORY; degrades gracefully otherwise.
# When neither signal fires the release is a standard development_release.
# ----------------------------------------------------------------------------
if [ -z "$TARGET_BRANCH" ]; then
    log_info "Branch context — inspecting commit $COMMIT for hotfix signal"

    HEAD_SUBJECT=$(git log -1 --format='%s' "$COMMIT" 2>/dev/null || echo "")
    SCENARIO=""

    case "$HEAD_SUBJECT" in
        hotfix:*|hotfix\(*)
            SCENARIO="hotfix_to_main"
            log_info "Hotfix detected via commit type convention: $HEAD_SUBJECT"
            ;;
    esac

    if [ -z "$SCENARIO" ] && command -v gh >/dev/null 2>&1 && [ -n "${GITHUB_REPOSITORY:-}" ]; then
        HEAD_REF=$(gh api "/repos/${GITHUB_REPOSITORY}/commits/${COMMIT}/pulls" \
            --jq '.[0].head.ref' 2>/dev/null || echo "")
        case "$HEAD_REF" in
            ${HOTFIX_PREFIX}*)
                SCENARIO="hotfix_to_main"
                log_info "Hotfix detected via GitHub API PR head ref: $HEAD_REF"
                ;;
        esac
    fi

    if [ -z "$SCENARIO" ]; then
        SCENARIO="development_release"
        log_info "Scenario: Development Release (no hotfix signal found)"
    fi

    echo "SCENARIO=$SCENARIO" > /tmp/scenario.env
    echo ""
    exit 0
fi

# ----------------------------------------------------------------------------
# PR context: dispatch on target branch (unchanged behaviour)
# ----------------------------------------------------------------------------
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
