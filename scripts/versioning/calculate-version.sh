#!/bin/sh
# =============================================================================
# calculate-version.sh - Calculate next version based on commits
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/../lib/common.sh"
. "${SCRIPT_DIR}/../lib/config-parser.sh"

# Load scenario
load_env "/tmp/scenario.env"

# Only calculate version for development releases
if [ "$SCENARIO" != "development_release" ]; then
    exit 0
fi

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
# Get latest tag from destination branch
# =============================================================================
TAG_PATTERN=$(get_tag_pattern)
LATEST_TAG=$(git tag --sort=-v:refname | \
    grep -E "$TAG_PATTERN" | head -n 1 || echo "")

if [ -z "$LATEST_TAG" ]; then
    log_info "No version tags found in ${VERSIONING_TARGET_BRANCH}"
    log_info "Starting from initial values"
    echo ""
    PERIOD=$PERIOD_INITIAL
    MAJOR=$MAJOR_INITIAL
    MINOR=$MINOR_INITIAL
else
    log_info "Latest tag in ${VERSIONING_TARGET_BRANCH}: $LATEST_TAG"

    # Parse components from tag using dynamic helpers
    VERSION=$(parse_tag_to_version "$LATEST_TAG")
    parse_version_components "$VERSION"
    PERIOD=$PARSED_PERIOD
    MAJOR=$PARSED_MAJOR
    MINOR=$PARSED_MINOR

    CURRENT_VER=$(build_version_string "$PERIOD" "$MAJOR" "$MINOR")
    log_info "Current version: ${CURRENT_VER}"
    echo ""
fi

# =============================================================================
# Get LAST commit to determine version bump
# =============================================================================
if [ -n "$IGNORE_PATTERN" ]; then
    COMMITS=$(git log origin/${VERSIONING_TARGET_BRANCH}..HEAD \
        --no-merges \
        --pretty=format:"%s" | \
        grep -vE "$IGNORE_PATTERN" || true)
else
    COMMITS=$(git log origin/${VERSIONING_TARGET_BRANCH}..HEAD \
        --no-merges \
        --pretty=format:"%s")
fi

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
    log_info "Version: ${PERIOD}${VERSION_SEP}${MAJOR}${VERSION_SEP}${MINOR}"
elif [ -n "$MINOR_PATTERN" ] && echo "$LAST_COMMIT" | grep -qE "$MINOR_PATTERN"; then
    BUMP_TYPE="minor"
    MINOR=$((MINOR + 1))
    log_info "Detected: MINOR bump"
    log_info "Version: ${PERIOD}${VERSION_SEP}${MAJOR}${VERSION_SEP}${MINOR}"
else
    log_info "Detected: Timestamp update only (no version bump)"
    log_info "Version: ${PERIOD}${VERSION_SEP}${MAJOR}${VERSION_SEP}${MINOR} (unchanged)"
fi

echo ""

# =============================================================================
# Build the full version tag (with or without timestamp)
# =============================================================================
CURRENT_VERSION=$(build_version_string "$PERIOD" "$MAJOR" "$MINOR")
NEXT_VERSION=$(build_full_tag "$CURRENT_VERSION")

log_info "Next version will be: $NEXT_VERSION"
if is_component_enabled "timestamp"; then
    log_info "Timestamp: $(date +"$(get_timestamp_format)") ($(get_timezone))"
fi
echo ""

# =============================================================================
# Check if tag already exists (collision)
# =============================================================================
if git rev-parse "$NEXT_VERSION" >/dev/null 2>&1; then
    log_info "Tag $NEXT_VERSION already exists"
    log_info "Pipeline will handle collision by waiting or adding suffix"
fi

# =============================================================================
# Export for changelog generation and tagging
# =============================================================================
write_state "/tmp/next_version.txt" "$NEXT_VERSION"
write_state "/tmp/bump_type.txt" "$BUMP_TYPE"

log_success "Version calculation complete"
