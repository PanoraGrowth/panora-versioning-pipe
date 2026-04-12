#!/bin/sh
# ------------------------------------------------------------------------------
# detect-scenario.sh
#
# Detects the pipeline scenario based on source and target branches of the PR
# (PR context) or the merge commit subject (branch context post-merge).
#
# Platform-agnostic: uses only git commands, no GitHub/Bitbucket APIs, no gh CLI,
# no platform-specific env vars. Works identically on GitHub Actions, Bitbucket
# Pipelines, GitLab CI, or a local git host.
#
# Branch context detection strategy (post-merge on the tag branch):
#   - Read HEAD commit subject. If it starts with "{keyword}:" or "{keyword}("
#     (config-driven via hotfix.keyword), scenario is "hotfix".
#   - If HEAD is a merge commit (2+ parents), ALSO check the subject of the
#     second parent (the branch-side parent). This covers the "merge commit"
#     merge style where the HEAD subject is "Merge pull request #N from ..."
#     and the real hotfix signal lives on the merged branch tip.
#   - Otherwise, scenario is "development_release".
#
# PR context detection strategy (pre-merge):
#   - Dispatch on TARGET_BRANCH vs PROD_BRANCH/PREPROD_BRANCH/DEV_BRANCH and
#     SOURCE_BRANCH patterns, using hotfix.keyword as the branch prefix
#     heuristic (e.g. "hotfix/*" by convention). This is the PR-preview path
#     used by pr-versioning.yml to comment the expected bump on the PR.
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

# Get hotfix detection keyword from config (default "hotfix")
HOTFIX_KEYWORD=$(get_hotfix_keyword)

# ----------------------------------------------------------------------------
# Branch context (no PR target): called by branch-pipeline.sh on the tag
# branch after a merge. The merge commit subject is the ONLY source of truth
# for hotfix detection. No API calls, no branch-name recovery — pure git.
# ----------------------------------------------------------------------------
if [ -z "$TARGET_BRANCH" ]; then
    log_info "Branch context — inspecting commit $COMMIT for hotfix signal"
    log_info "Hotfix keyword (from config): ${HOTFIX_KEYWORD}"

    HEAD_SUBJECT=$(git log -1 --format='%s' "$COMMIT" 2>/dev/null || echo "")
    SCENARIO=""

    # Check 1: HEAD subject. Covers squash merges (subject = PR title) and
    # rebase merges (subject = last replayed commit from the branch).
    case "$HEAD_SUBJECT" in
        ${HOTFIX_KEYWORD}:*|${HOTFIX_KEYWORD}\(*)
            SCENARIO="hotfix"
            log_info "Hotfix detected via HEAD commit subject: $HEAD_SUBJECT"
            ;;
    esac

    # Check 2: merge commit parent. Covers the traditional 3-way merge where
    # HEAD.subject is "Merge pull request #N from ..." but the branch tip
    # (HEAD's second parent) carries the real hotfix commit.
    if [ -z "$SCENARIO" ]; then
        PARENTS=$(git log -1 --format='%P' "$COMMIT" 2>/dev/null || echo "")
        PARENT_COUNT=$(echo "$PARENTS" | wc -w | tr -d ' ')
        if [ "${PARENT_COUNT:-0}" -ge 2 ] 2>/dev/null; then
            BRANCH_PARENT=$(echo "$PARENTS" | awk '{print $2}')
            BRANCH_PARENT_SUBJECT=$(git log -1 --format='%s' "$BRANCH_PARENT" 2>/dev/null || echo "")
            case "$BRANCH_PARENT_SUBJECT" in
                ${HOTFIX_KEYWORD}:*|${HOTFIX_KEYWORD}\(*)
                    SCENARIO="hotfix"
                    log_info "Hotfix detected via merge commit parent: $BRANCH_PARENT_SUBJECT"
                    ;;
            esac
        fi
    fi

    if [ -z "$SCENARIO" ]; then
        SCENARIO="development_release"
        log_info "Scenario: Development Release (no hotfix signal in HEAD or parents)"
    fi

    echo "SCENARIO=$SCENARIO" > /tmp/scenario.env
    echo ""
    exit 0
fi

# ----------------------------------------------------------------------------
# PR context: dispatch on target branch for preview comment on the PR.
# Uses the hotfix keyword as a branch prefix heuristic (e.g. "hotfix/*").
# ----------------------------------------------------------------------------
HOTFIX_BRANCH_PATTERN="${HOTFIX_KEYWORD}/"

case "$TARGET_BRANCH" in
    "$DEV_BRANCH")
        # Any branch targeting development = development release
        SCENARIO="development_release"
        echo "Scenario: Development Release (Changelog + Tag)"
        ;;

    "$PREPROD_BRANCH")
        # Check if it is a hotfix or a promotion
        case "$SOURCE_BRANCH" in
            ${HOTFIX_BRANCH_PATTERN}*)
                SCENARIO="hotfix"
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
            ${HOTFIX_BRANCH_PATTERN}*)
                SCENARIO="hotfix"
                echo "Scenario: Hotfix to Production (Changelog + Tag)"
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
