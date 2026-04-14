#!/bin/sh
# shellcheck shell=ash
# =============================================================================
# validate-commits.sh - Validate commits follow configured format
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/config-parser.sh
. "${SCRIPT_DIR}/../lib/config-parser.sh"

# Load scenario
load_env "/tmp/scenario.env"

# Only validate for development releases and hotfixes
case "$SCENARIO" in
    development_release|hotfix)
        ;;
    *)
        exit 0
        ;;
esac

log_section "VALIDATING COMMIT FORMAT"
echo ""

# =============================================================================
# Load configuration
# =============================================================================
IGNORE_PATTERN=$(get_ignore_patterns_regex)
TICKET_PREFIX_PATTERN=$(build_ticket_prefix_pattern)
TICKET_FULL_PATTERN=$(build_ticket_full_pattern)
COMMIT_TYPES=$(get_commit_types_pattern)
EXAMPLE_PREFIX=$(get_example_prefix)

# =============================================================================
# Get commits (excluding ignored patterns)
# =============================================================================
if [ -n "$IGNORE_PATTERN" ]; then
    COMMITS=$(git log "origin/${VERSIONING_TARGET_BRANCH}..HEAD" \
        --no-merges \
        --pretty=format:"%s" | \
        grep -vE "$IGNORE_PATTERN" || true)
else
    COMMITS=$(git log "origin/${VERSIONING_TARGET_BRANCH}..HEAD" \
        --no-merges \
        --pretty=format:"%s")
fi

if [ -z "$COMMITS" ]; then
    log_error "No valid commits found in this PR"
    exit 1
fi

log_info "Commits in this PR:"
echo ""

# Display all commits with validation status
echo "$COMMITS" | while IFS= read -r commit; do
    if [ -z "$TICKET_PREFIX_PATTERN" ]; then
        # No prefix validation required
        echo "  - $commit"
    elif echo "$commit" | grep -qE "$TICKET_PREFIX_PATTERN"; then
        echo "  + $commit"
    else
        echo "  x INVALID: $commit"
    fi
done
echo ""

# =============================================================================
# VALIDATION 1: ALL commits must have ticket prefix (if required)
# =============================================================================
if require_ticket_prefix; then
    INVALID_PREFIX=$(echo "$COMMITS" | grep -vE "$TICKET_PREFIX_PATTERN" || true)

    if [ -n "$INVALID_PREFIX" ]; then
        PREFIXES=$(get_ticket_prefixes_pattern | tr '|' ', ')
        log_section "ERROR: COMMITS WITHOUT TICKET PREFIX"
        echo ""
        log_info "ALL commits must start with: ${PREFIXES}-XXXX -"
        echo ""
        log_info "Invalid commits:"
        echo "$INVALID_PREFIX" | while IFS= read -r commit; do
            echo "  x $commit"
        done
        echo ""
        log_info "Examples:"
        log_info "  ${EXAMPLE_PREFIX}-1234 - feat: add new feature"
        log_info "  ${EXAMPLE_PREFIX}-1234 - fix: correct bug"
        log_info "  ${EXAMPLE_PREFIX}-1234 - minor: release version"
        echo ""
        exit 1
    fi
fi

# Skip prefix validation for conventional commits (no ticket prefix needed)
if is_conventional_commits && require_ticket_prefix; then
    log_info "Conventional commits format: ticket prefix validation skipped"
fi

# =============================================================================
# VALIDATION 2: commits must have complete format (scope driven by changelog.mode)
# =============================================================================
if require_commit_types; then
    if require_commit_types_for_all; then
        # changelog.mode: full — ALL commits must be typed
        INVALID_COMMITS=$(echo "$COMMITS" | grep -vE "$TICKET_FULL_PATTERN" || true)

        if [ -n "$INVALID_COMMITS" ]; then
            log_section "ERROR: COMMITS NOT WELL-FORMED"
            echo ""
            log_info "changelog.mode is 'full' — ALL commits must have a valid type."
            echo ""

            if is_conventional_commits; then
                log_info "Each commit must follow Conventional Commits format:"
                log_info "  <type>(scope): <message>  or  <type>: <message>"
            elif has_ticket_prefixes; then
                log_info "Each commit must follow format:"
                log_info "  ${EXAMPLE_PREFIX}-XXXX - <type>: <message>"
            else
                log_info "Each commit must include a commit type:"
                log_info "  <type>: <message>"
            fi
            echo ""
            log_info "Invalid commits:"
            echo "$INVALID_COMMITS" | while IFS= read -r commit; do
                echo "  x $commit"
            done
            echo ""
            log_info "Valid types: $(echo "$COMMIT_TYPES" | tr '|' ', ')"
            echo ""
            log_info "Examples:"
            if is_conventional_commits; then
                log_info "  feat(cluster-ecs): add new ECS config"
                log_info "  fix(alb): correct listener rules"
                log_info "  minor(service-ecs): release notifications module"
                log_info "  feat: add general feature (no scope)"
            elif has_ticket_prefixes; then
                log_info "  ${EXAMPLE_PREFIX}-1234 - feat: add new feature"
                log_info "  ${EXAMPLE_PREFIX}-1234 - fix: resolve bug"
                log_info "  ${EXAMPLE_PREFIX}-1234 - minor: release new features"
                log_info "  ${EXAMPLE_PREFIX}-1234 - major: breaking changes"
            else
                log_info "  feat: add new feature"
                log_info "  fix: resolve bug"
                log_info "  minor: release new features"
            fi
            echo ""
            exit 1
        fi
    else
        # changelog.mode: last_commit — only the last commit must be typed
        LAST_COMMIT=$(echo "$COMMITS" | head -n 1)

        log_info "Last commit (determines version):"
        echo "  -> $LAST_COMMIT"
        echo ""

        if ! echo "$LAST_COMMIT" | grep -qE "$TICKET_FULL_PATTERN"; then
            log_section "ERROR: LAST COMMIT NOT WELL-FORMED"
            echo ""

            if is_conventional_commits; then
                log_info "The LAST commit must follow Conventional Commits format:"
                log_info "  <type>(scope): <message>  or  <type>: <message>"
            elif has_ticket_prefixes; then
                log_info "The LAST commit must follow format:"
                log_info "  ${EXAMPLE_PREFIX}-XXXX - <type>: <message>"
            else
                log_info "The LAST commit must include a commit type:"
                log_info "  <type>: <message>"
            fi
            echo ""
            log_info "Last commit:"
            echo "  x $LAST_COMMIT"
            echo ""
            log_info "Valid types: $(echo "$COMMIT_TYPES" | tr '|' ', ')"
            echo ""
            log_info "Examples:"
            if is_conventional_commits; then
                log_info "  feat(cluster-ecs): add new ECS config"
                log_info "  fix(alb): correct listener rules"
                log_info "  minor(service-ecs): release notifications module"
                log_info "  feat: add general feature (no scope)"
            elif has_ticket_prefixes; then
                log_info "  ${EXAMPLE_PREFIX}-1234 - feat: add new feature"
                log_info "  ${EXAMPLE_PREFIX}-1234 - fix: resolve bug"
                log_info "  ${EXAMPLE_PREFIX}-1234 - minor: release new features"
                log_info "  ${EXAMPLE_PREFIX}-1234 - major: breaking changes"
            else
                log_info "  feat: add new feature"
                log_info "  fix: resolve bug"
                log_info "  minor: release new features"
            fi
            echo ""
            exit 1
        fi
    fi
fi

echo ""
if require_ticket_prefix; then
    log_success "+ All commits have valid ticket prefix"
fi
if require_commit_types_for_all; then
    log_success "+ All commits are well-formed"
else
    log_success "+ Last commit is well-formed"
fi
