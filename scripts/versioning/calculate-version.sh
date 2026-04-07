#!/bin/sh
# =============================================================================
# calculate-version.sh - Calculate next version based on commits
# =============================================================================
# Context-aware: works in both PR context (VERSIONING_TARGET_BRANCH set)
# and branch context (tag-based range).
# Writes: /tmp/next_version.txt, /tmp/bump_type.txt, /tmp/latest_tag.txt
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/../lib/common.sh"
. "${SCRIPT_DIR}/../lib/config-parser.sh"

log_section "CALCULATING VERSION"

# =============================================================================
# Load configuration
# =============================================================================
VERSION_SEP=$(get_version_separator)
IGNORE_PATTERN=$(get_ignore_patterns_regex)

# Get initial values from config
PERIOD_INITIAL=$(get_component_initial "period" "0")
MAJOR_INITIAL=$(get_component_initial "major" "0")
MINOR_INITIAL=$(get_component_initial "minor" "0")

# Build bump patterns from config
MAJOR_PATTERN=$(build_bump_pattern "major")
MINOR_PATTERN=$(build_bump_pattern "minor")

# =============================================================================
# Get latest tag
# =============================================================================
TAG_PATTERN=$(get_tag_pattern)
LATEST_TAG=$(git tag --sort=-v:refname | \
    grep -E "$TAG_PATTERN" | head -n 1 || echo "")

# Save latest tag for other scripts (e.g. CHANGELOG_BASE_REF)
write_state "/tmp/latest_tag.txt" "${LATEST_TAG:-}"

if [ -z "$LATEST_TAG" ]; then
    log_info "No version tags found, starting from initial values"
    PERIOD=$PERIOD_INITIAL
    MAJOR=$MAJOR_INITIAL
    MINOR=$MINOR_INITIAL
else
    log_info "Latest tag: $LATEST_TAG"
    VERSION=$(parse_tag_to_version "$LATEST_TAG")
    parse_version_components "$VERSION"
    PERIOD=$PARSED_PERIOD
    MAJOR=$PARSED_MAJOR
    MINOR=$PARSED_MINOR
    CURRENT_VER=$(build_version_string "$PERIOD" "$MAJOR" "$MINOR")
    log_info "Current version: ${CURRENT_VER}"
fi

echo ""

# =============================================================================
# Determine commit range based on context
# =============================================================================
if [ -n "${VERSIONING_TARGET_BRANCH:-}" ]; then
    # PR context: use target branch
    COMMIT_RANGE="origin/${VERSIONING_TARGET_BRANCH}..HEAD"
    log_info "Context: PR (target: $VERSIONING_TARGET_BRANCH)"
else
    # Branch context: use latest tag
    if [ -n "$LATEST_TAG" ]; then
        COMMIT_RANGE="${LATEST_TAG}..HEAD"
        log_info "Context: Branch (since tag: $LATEST_TAG)"
    else
        COMMIT_RANGE="HEAD"
        log_info "Context: Branch (no previous tags, using all commits)"
    fi
fi

# =============================================================================
# Get commits (excluding ignored patterns)
# =============================================================================
if [ -n "$IGNORE_PATTERN" ]; then
    COMMITS=$(git log $COMMIT_RANGE \
        --no-merges \
        --pretty=format:"%s" | \
        grep -vE "$IGNORE_PATTERN" || true)
else
    COMMITS=$(git log $COMMIT_RANGE \
        --no-merges \
        --pretty=format:"%s")
fi

if [ -z "$COMMITS" ]; then
    log_info "No new commits found - skipping version calculation"
    write_state "/tmp/next_version.txt" ""
    write_state "/tmp/bump_type.txt" ""
    exit 0
fi

# Get LAST commit to determine bump
LAST_COMMIT=$(echo "$COMMITS" | head -n 1)
log_info "Last commit: $LAST_COMMIT"
echo ""

# =============================================================================
# Detect bump type based on LAST commit only
# =============================================================================
BUMP_TYPE="timestamp_only"

if [ -n "$MAJOR_PATTERN" ] && echo "$LAST_COMMIT" | grep -qE "$MAJOR_PATTERN"; then
    BUMP_TYPE="major"
    MAJOR=$((MAJOR + 1))
    MINOR=0
    log_info "Detected: MAJOR bump"
elif [ -n "$MINOR_PATTERN" ] && echo "$LAST_COMMIT" | grep -qE "$MINOR_PATTERN"; then
    BUMP_TYPE="minor"
    MINOR=$((MINOR + 1))
    log_info "Detected: MINOR bump"
else
    log_info "Detected: Timestamp update only (no version bump)"
fi

echo ""

# =============================================================================
# Build the full version tag
# =============================================================================
CURRENT_VERSION=$(build_version_string "$PERIOD" "$MAJOR" "$MINOR")
NEXT_VERSION=$(build_full_tag "$CURRENT_VERSION")

log_info "Next version will be: $NEXT_VERSION"
if is_component_enabled "timestamp"; then
    log_info "Timestamp: $(date +"$(get_timestamp_format)") ($(get_timezone))"
fi
echo ""

# =============================================================================
# Handle tag collision (append -2, -3, etc. if tag exists)
# =============================================================================
if git rev-parse "$NEXT_VERSION" >/dev/null 2>&1; then
    log_info "Tag $NEXT_VERSION already exists, adding suffix"
    SUFFIX=2
    while git rev-parse "${NEXT_VERSION}-${SUFFIX}" >/dev/null 2>&1; do
        SUFFIX=$((SUFFIX + 1))
    done
    NEXT_VERSION="${NEXT_VERSION}-${SUFFIX}"
    log_info "New tag with suffix: $NEXT_VERSION"
    echo ""
fi

# =============================================================================
# Export for changelog generation and tagging
# =============================================================================
write_state "/tmp/next_version.txt" "$NEXT_VERSION"
write_state "/tmp/bump_type.txt" "$BUMP_TYPE"

log_success "Version calculation complete"
