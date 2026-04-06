#!/bin/sh
# ============================================================================
# Script: branch-pipeline.sh
# Description: Main orchestrator for branch pipeline (create tags)
# Inputs: VERSIONING_BRANCH, VERSIONING_COMMIT
# Outputs: Version tag created and pushed
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AUTOMATIONS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load common functions and config
. "${AUTOMATIONS_DIR}/lib/common.sh"
. "${AUTOMATIONS_DIR}/lib/config-parser.sh"

log_section "BRANCH PIPELINE - TAG CREATION"
log_info "Branch: $VERSIONING_BRANCH"
echo ""

# Get tag branch from config
TAG_BRANCH=$(get_tag_branch)

# Only create tags for configured branch
if [ "$VERSIONING_BRANCH" != "$TAG_BRANCH" ]; then
    log_info "Tag creation only runs on $TAG_BRANCH branch"
    log_info "Current branch: $VERSIONING_BRANCH"
    log_info "Skipping tag creation"
    exit 0
fi

# ============================================================================
# Load configuration
# ============================================================================
VERSION_SEP=$(get_version_separator)

# Get initial values from config
PERIOD_INITIAL=$(get_component_initial "period" "0")
MAJOR_INITIAL=$(get_component_initial "major" "0")
MINOR_INITIAL=$(get_component_initial "minor" "0")

# Build bump patterns from config
MAJOR_PATTERN=$(build_bump_pattern "major")
MINOR_PATTERN=$(build_bump_pattern "minor")

# ============================================================================
# Calculate version
# ============================================================================

# Get latest tag
TAG_PATTERN=$(get_tag_pattern)
LATEST_TAG=$(git tag --sort=-v:refname | \
    grep -E "$TAG_PATTERN" | head -n 1 || echo "")

if [ -z "$LATEST_TAG" ]; then
    log_info "No version tags found, starting from initial values"
    PERIOD=$PERIOD_INITIAL
    MAJOR=$MAJOR_INITIAL
    MINOR=$MINOR_INITIAL
else
    log_info "Latest tag: $LATEST_TAG"

    # Parse components from tag using dynamic helpers
    VERSION=$(parse_tag_to_version "$LATEST_TAG")
    parse_version_components "$VERSION"
    PERIOD=$PARSED_PERIOD
    MAJOR=$PARSED_MAJOR
    MINOR=$PARSED_MINOR

    CURRENT_VER=$(build_version_string "$PERIOD" "$MAJOR" "$MINOR")
    log_info "Current version: ${CURRENT_VER}"
fi

echo ""

# Get commits since last tag (excluding merges and changelog updates)
if [ -z "$LATEST_TAG" ]; then
    COMMITS=$(git log --no-merges --pretty=format:"%s" HEAD | \
        grep -vE "^(fixup!|squash!|Revert|Merge|chore\(release\)|chore: update CHANGELOG)" || true)
else
    COMMITS=$(git log --no-merges --pretty=format:"%s" ${LATEST_TAG}..HEAD | \
        grep -vE "^(fixup!|squash!|Revert|Merge|chore\(release\)|chore: update CHANGELOG)" || true)
fi

if [ -z "$COMMITS" ]; then
    log_info "No new commits since last tag - skipping tag creation"
    exit 0
fi

# Get LAST commit to determine bump
LAST_COMMIT=$(echo "$COMMITS" | head -n 1)
log_info "Last commit: $LAST_COMMIT"
echo ""

# Detect bump type using patterns from config
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
    log_info "Detected: Timestamp update only"
fi

CURRENT_VERSION=$(build_version_string "$PERIOD" "$MAJOR" "$MINOR")
log_info "Version: $CURRENT_VERSION"
echo ""

# Build full tag (with or without timestamp)
NEW_TAG=$(build_full_tag "$CURRENT_VERSION")

log_info "New tag will be: $NEW_TAG"
if is_component_enabled "timestamp"; then
    log_info "Timestamp: $(date +"$(get_timestamp_format)") ($(get_timezone))"
fi
echo ""

# Check if tag already exists
if git rev-parse "$NEW_TAG" >/dev/null 2>&1; then
    log_info "Tag $NEW_TAG already exists, adding suffix"
    SUFFIX=2
    while git rev-parse "${NEW_TAG}-${SUFFIX}" >/dev/null 2>&1; do
        SUFFIX=$((SUFFIX + 1))
    done
    NEW_TAG="${NEW_TAG}-${SUFFIX}"
    log_info "New tag with suffix: $NEW_TAG"
    echo ""
fi

# ============================================================================
# Create and push tag
# ============================================================================

echo "=========================================="
echo "  CREATING VERSION TAG"
echo "=========================================="
echo "Tag: $NEW_TAG"
echo ""

git tag -a "$NEW_TAG" \
    -m "Release version $CURRENT_VERSION ($BUMP_TYPE)" \
    -m "" \
    -m "Automated by CI pipeline" \
    -m "Branch: $VERSIONING_BRANCH" \
    -m "Commit: $VERSIONING_COMMIT" \
    -m "Timestamp: $(date +"%Y-%m-%d %H:%M:%S %Z")"

log_success "Tag created successfully"
echo ""

log_info "Pushing tag to remote repository..."
git push origin "$NEW_TAG"

echo ""
echo "=========================================="
echo "  VERSION TAG CREATED SUCCESSFULLY"
echo "=========================================="
echo "Previous Tag:      $LATEST_TAG"
echo "New Version:       $CURRENT_VERSION"
echo "Bump Type:         $BUMP_TYPE"
echo "New Tag:           $NEW_TAG"
echo "Branch:            $VERSIONING_BRANCH"
echo "Commit:            $VERSIONING_COMMIT"
echo "=========================================="
