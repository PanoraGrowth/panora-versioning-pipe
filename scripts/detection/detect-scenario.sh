#!/bin/sh
# shellcheck shell=ash
set -e
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
#   Primary source of truth: branch name — consistent with PR context.
#   Three checks in order:
#   1. HEAD commit subject. Covers squash merges (subject = PR title starts with
#      the hotfix keyword, e.g. "hotfix: fix auth") and rebase merges (last
#      replayed commit from the branch).
#   2. For merge commits (2+ parents): extract the source branch name from the
#      merge commit subject ("Merge pull request #N from org/hotfix/fix-auth")
#      and match it against the hotfix branch prefix. This is the primary fix for
#      the inconsistency: a developer merging from "hotfix/fix-auth" with a
#      conventional commit subject ("fix: resolve auth bug") is now correctly
#      detected as a hotfix without requiring the keyword in the commit subject.
#   3. For merge commits: also check the subject of the second parent (the
#      branch-side parent). Covers edge cases where the merge commit subject
#      does not embed the branch name (non-GitHub-style merge messages).
#   - Otherwise, scenario is "development_release".
#
# PR context detection strategy (pre-merge):
#   - Dispatch on TARGET_BRANCH vs TAG_BRANCH and hotfix_targets list, using
#     the hotfix keyword base (first pattern, stripped of globs) as the branch
#     prefix heuristic (e.g. "hotfix/*").
#     This is the PR-preview path used by pr-versioning.yml to comment the
#     expected bump on the PR.
# ------------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/config-parser.sh
. "${SCRIPT_DIR}/../lib/config-parser.sh"

log_section "DETECTING PIPELINE SCENARIO"

SOURCE_BRANCH="${VERSIONING_BRANCH}"
TARGET_BRANCH="${VERSIONING_TARGET_BRANCH}"
COMMIT="${VERSIONING_COMMIT:-HEAD}"

log_info "Source Branch: $SOURCE_BRANCH"
log_info "Target Branch: ${TARGET_BRANCH:-<branch context>}"
echo ""

# Get branch config
TAG_BRANCH=$(get_tag_branch)

# Get hotfix detection patterns from config (list of glob patterns)
HOTFIX_KEYWORDS=$(get_hotfix_keywords)
# Base keyword for branch prefix matching (PR context and branch name recovery)
HOTFIX_KEYWORD_BASE=$(get_hotfix_keyword)
# Branch prefix pattern derived from the base keyword (e.g. "hotfix/")
# Used in both PR context (source branch matching) and branch context (merged
# branch name recovery from merge commit subjects).
HOTFIX_BRANCH_PATTERN="${HOTFIX_KEYWORD_BASE}/"

# Match a commit subject against the hotfix keyword patterns.
# Returns 0 (true) if any pattern matches, 1 (false) otherwise.
matches_hotfix_keyword() {
    local subject="$1"
    echo "$HOTFIX_KEYWORDS" | while IFS= read -r pattern; do
        [ -z "$pattern" ] && continue
        # shellcheck disable=SC2254
        case "$subject" in
            $pattern) echo "match"; return 0 ;;
        esac
    done | grep -q "match"
}

# Match a branch name against the hotfix branch prefix (e.g. "hotfix/").
# Returns 0 (true) if the branch starts with the prefix, 1 (false) otherwise.
matches_hotfix_branch() {
    local branch="$1"
    case "$branch" in
        ${HOTFIX_BRANCH_PATTERN}*) return 0 ;;
    esac
    return 1
}

# Extract the source branch name from a GitHub-style merge commit subject.
# "Merge pull request #N from org/hotfix/fix-auth" → "hotfix/fix-auth"
# Returns empty string if the subject does not match the expected format.
extract_branch_from_merge_subject() {
    local subject="$1"
    case "$subject" in
        "Merge pull request #"*)
            echo "$subject" | sed 's|.*from [^/]*/||'
            ;;
        *)
            echo ""
            ;;
    esac
}

# ----------------------------------------------------------------------------
# Branch context (no PR target): called by branch-pipeline.sh on the tag
# branch after a merge. Branch name is the primary source of truth (consistent
# with PR context). Falls back to commit subject checks when the branch name
# cannot be recovered from the git history (e.g. squash merges).
# No API calls — pure git.
# ----------------------------------------------------------------------------
if [ -z "$TARGET_BRANCH" ]; then
    log_info "Branch context — inspecting commit $COMMIT for hotfix signal"
    log_info "Hotfix keywords (from config):"
    echo "$HOTFIX_KEYWORDS" | while IFS= read -r p; do [ -n "$p" ] && log_info "  - $p"; done
    log_info "Hotfix branch prefix: ${HOTFIX_BRANCH_PATTERN}"

    HEAD_SUBJECT=$(git log -1 --format='%s' "$COMMIT" 2>/dev/null || echo "")
    SCENARIO=""

    # Check 1: HEAD subject. Covers squash merges (subject = PR title) and
    # rebase merges (subject = last replayed commit from the branch).
    if matches_hotfix_keyword "$HEAD_SUBJECT"; then
        SCENARIO="hotfix"
        log_info "Hotfix detected via HEAD commit subject: $HEAD_SUBJECT"
    fi

    # Checks 2 and 3 only apply to merge commits (2+ parents).
    PARENTS=$(git log -1 --format='%P' "$COMMIT" 2>/dev/null || echo "")
    PARENT_COUNT=$(echo "$PARENTS" | wc -w | tr -d ' ')

    # Check 2: for merge commits, try to recover the source branch name from the
    # merge commit subject. GitHub formats this as:
    # "Merge pull request #N from org/hotfix/fix-auth"
    # This is the primary fix for the PR-context vs branch-context inconsistency:
    # a branch named "hotfix/fix-auth" is detected as hotfix regardless of what
    # the individual commits say. This is the same signal PR context uses.
    if [ -z "$SCENARIO" ] && [ "${PARENT_COUNT:-0}" -ge 2 ] 2>/dev/null; then
        MERGED_BRANCH=$(extract_branch_from_merge_subject "$HEAD_SUBJECT")
        if [ -n "$MERGED_BRANCH" ] && matches_hotfix_branch "$MERGED_BRANCH"; then
            SCENARIO="hotfix"
            log_info "Hotfix detected via merged branch name: $MERGED_BRANCH"
        fi
    fi

    # Check 3: merge commit parent subject. Covers edge cases where the merge
    # commit subject does not embed the branch name (non-GitHub-style merge
    # messages) but the branch tip commit carries the hotfix keyword.
    if [ -z "$SCENARIO" ] && [ "${PARENT_COUNT:-0}" -ge 2 ] 2>/dev/null; then
        BRANCH_PARENT=$(echo "$PARENTS" | awk '{print $2}')
        BRANCH_PARENT_SUBJECT=$(git log -1 --format='%s' "$BRANCH_PARENT" 2>/dev/null || echo "")
        if matches_hotfix_keyword "$BRANCH_PARENT_SUBJECT"; then
            SCENARIO="hotfix"
            log_info "Hotfix detected via merge commit parent: $BRANCH_PARENT_SUBJECT"
        fi
    fi

    if [ -z "$SCENARIO" ]; then
        SCENARIO="development_release"
        log_info "Scenario: Development Release (no hotfix signal in HEAD, branch name, or parents)"
    fi

    echo "SCENARIO=$SCENARIO" > /tmp/scenario.env
    echo ""
    exit 0
fi

# ----------------------------------------------------------------------------
# PR context: dispatch on target branch.
# - tag_on target → development_release (any source)
# - hotfix_targets target → hotfix (hotfix/ source) or promotion_to_main
#   (source == tag_on) or unknown (anything else)
# ----------------------------------------------------------------------------
if [ "$TARGET_BRANCH" = "$TAG_BRANCH" ]; then
    SCENARIO="development_release"
    echo "Scenario: Development Release (Changelog + Tag)"
elif is_hotfix_target "$TARGET_BRANCH"; then
    case "$SOURCE_BRANCH" in
        ${HOTFIX_BRANCH_PATTERN}*)
            SCENARIO="hotfix"
            echo "Scenario: Hotfix (Changelog + Tag)"
            ;;
        "$TAG_BRANCH")
            SCENARIO="promotion_to_main"
            echo "Scenario: Promotion (No action)"
            ;;
        *)
            SCENARIO="unknown"
            echo "Scenario: Unknown - No pipeline action"
            ;;
    esac
else
    SCENARIO="unknown"
    echo "Scenario: Unknown - No pipeline action"
fi

# Save scenario for other scripts to read
echo "SCENARIO=$SCENARIO" > /tmp/scenario.env
echo ""
