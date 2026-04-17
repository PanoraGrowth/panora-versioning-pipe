#!/bin/sh
# shellcheck shell=ash
set -e
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

# =============================================================================
# VALIDATION 3: PR title must follow the same format as commits
# Applies when VERSIONING_PR_TITLE is set (GitHub Actions PR event) and
# require_commit_types is enabled. In squash merge, the PR title becomes the
# squash commit subject — the one that determines the version bump. Validating
# it here prevents bump:none surprises at merge time.
# Skipped silently when VERSIONING_PR_TITLE is empty (Bitbucket, generic CI).
# =============================================================================
if require_commit_types && [ -n "${VERSIONING_PR_TITLE:-}" ]; then
    log_info "PR title: ${VERSIONING_PR_TITLE}"
    echo ""
    # A PR title is valid if it matches the commit format OR a hotfix keyword pattern.
    # Hotfix keyword patterns (e.g. "[Hh]otfix/*") are glob-style — use case matching.
    _PR_TITLE_VALID=0
    if echo "$VERSIONING_PR_TITLE" | grep -qE "$TICKET_FULL_PATTERN"; then
        _PR_TITLE_VALID=1
    else
        _HOTFIX_KEYWORDS=$(get_hotfix_keywords)
        while IFS= read -r _kw; do
            [ -z "$_kw" ] && continue
            # Pattern comes from a variable — use eval so bracket expressions
            # like [Hh]otfix/* expand correctly in the case pattern.
            # shellcheck disable=SC2254
            if eval "case \"\$VERSIONING_PR_TITLE\" in $_kw) true ;; *) false ;; esac" 2>/dev/null; then
                _PR_TITLE_VALID=1
                break
            fi
        done <<EOF
$_HOTFIX_KEYWORDS
EOF
    fi
    if [ "$_PR_TITLE_VALID" -eq 0 ]; then
        log_section "ERROR: PR TITLE NOT WELL-FORMED"
        echo ""
        log_info "The PR title must follow the same format as commits."
        log_info "In squash merge, the PR title becomes the commit that determines the version bump."
        echo ""
        if is_conventional_commits; then
            log_info "PR title must follow Conventional Commits format:"
            log_info "  <type>(scope): <message>  or  <type>: <message>"
        elif has_ticket_prefixes; then
            log_info "PR title must follow format:"
            log_info "  ${EXAMPLE_PREFIX}-XXXX - <type>: <message>"
        else
            log_info "PR title must include a commit type:"
            log_info "  <type>: <message>"
        fi
        echo ""
        log_info "Current PR title:"
        echo "  x ${VERSIONING_PR_TITLE}"
        echo ""
        log_info "Valid types: $(echo "$COMMIT_TYPES" | tr '|' ', ')"
        echo ""
        log_info "Examples:"
        if is_conventional_commits; then
            log_info "  feat: add new feature"
            log_info "  fix(auth): resolve token expiry"
            log_info "  chore: update dependencies"
        elif has_ticket_prefixes; then
            log_info "  ${EXAMPLE_PREFIX}-1234 - feat: add new feature"
            log_info "  ${EXAMPLE_PREFIX}-1234 - fix: resolve bug"
        else
            log_info "  feat: add new feature"
            log_info "  fix: resolve bug"
        fi
        echo ""
        exit 1
    fi
    log_success "+ PR title is well-formed"
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
