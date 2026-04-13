#!/bin/sh
# shellcheck shell=ash
# =============================================================================
# calculate-version.sh - Calculate next version based on commits
# =============================================================================
# Context-aware: works in both PR context (VERSIONING_TARGET_BRANCH set)
# and branch context (tag-based range).
# Writes: /tmp/next_version.txt, /tmp/bump_type.txt, /tmp/latest_tag.txt
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/config-parser.sh
. "${SCRIPT_DIR}/../lib/config-parser.sh"

log_section "CALCULATING VERSION"

# =============================================================================
# Load configuration
# =============================================================================
# shellcheck disable=SC2034
VERSION_SEP=$(get_version_separator)
IGNORE_PATTERN=$(get_ignore_patterns_regex)

# Get initial values from config
PERIOD_INITIAL=$(get_component_initial "period" "0")
MAJOR_INITIAL=$(get_component_initial "major" "0")
MINOR_INITIAL=$(get_component_initial "minor" "0")
PATCH_INITIAL=$(get_component_initial "patch" "0")

# Build bump patterns from config
MAJOR_PATTERN=$(build_bump_pattern "major")
MINOR_PATTERN=$(build_bump_pattern "minor")

# Read scenario written by detect-scenario.sh (or default). Branch-pipeline.sh
# invokes detect-scenario.sh BEFORE this script so /tmp/scenario.env is available.
# PR context may also pre-populate it. Missing file falls back to development_release.
SCENARIO=""
if [ -f /tmp/scenario.env ]; then
    # shellcheck disable=SC1091
    . /tmp/scenario.env
fi
[ -z "${SCENARIO:-}" ] && SCENARIO="development_release"

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
    PATCH=$PATCH_INITIAL
else
    log_info "Latest tag: $LATEST_TAG"
    VERSION=$(parse_tag_to_version "$LATEST_TAG")
    parse_version_components "$VERSION"
    PERIOD=$PARSED_PERIOD
    MAJOR=$PARSED_MAJOR
    MINOR=$PARSED_MINOR
    PATCH=$PARSED_PATCH
    CURRENT_VER=$(build_version_string "$PERIOD" "$MAJOR" "$MINOR" "$PATCH")
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
    COMMITS=$(git log "$COMMIT_RANGE" \
        --no-merges \
        --pretty=format:"%s" | \
        grep -vE "$IGNORE_PATTERN" || true)
else
    COMMITS=$(git log "$COMMIT_RANGE" \
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
# Detect bump type
# =============================================================================
# Hotfix scenario + patch.enabled=true → bump PATCH, produce .N tag.
# Hotfix scenario + patch.enabled=false → NO-OP: skip tag creation entirely and
#   emit a 3-line INFO log explaining why. The consumer opted out of the patch
#   component explicitly, so honoring that opt-out is the expected behavior.
# Non-hotfix scenarios → fall through to standard last-commit-wins detection.
BUMP_TYPE="timestamp_only"

if [ "$SCENARIO" = "hotfix" ]; then
    if is_component_enabled "patch"; then
        BUMP_TYPE="patch"
        PATCH=$((PATCH + 1))
        log_info "Detected: PATCH bump (hotfix scenario)"
    else
        log_info "Hotfix commit detected (\"$LAST_COMMIT\") but version.components.patch.enabled is false."
        log_info "Skipping tag creation (consumer opted out of patch component)."
        log_info "To enable hotfix tags, set version.components.patch.enabled: true in your .versioning.yml."
        write_state "/tmp/next_version.txt" ""
        write_state "/tmp/bump_type.txt" ""
        exit 0
    fi
elif [ -n "$MAJOR_PATTERN" ] && echo "$LAST_COMMIT" | grep -qE "$MAJOR_PATTERN"; then
    BUMP_TYPE="major"
    MAJOR=$((MAJOR + 1))
    MINOR=0
    PATCH=0
    log_info "Detected: MAJOR bump"
elif [ -n "$MINOR_PATTERN" ] && echo "$LAST_COMMIT" | grep -qE "$MINOR_PATTERN"; then
    BUMP_TYPE="minor"
    MINOR=$((MINOR + 1))
    PATCH=0
    log_info "Detected: MINOR bump"
else
    # No bump pattern matched — check if timestamp can differentiate
    if is_component_enabled "timestamp"; then
        log_info "Detected: Timestamp update only (no version bump)"
    else
        log_info "Detected: No version bump (commit type has bump: none)"
        write_state "/tmp/next_version.txt" ""
        write_state "/tmp/bump_type.txt" ""
        exit 0
    fi
fi

echo ""

# =============================================================================
# Build the full version tag
# =============================================================================
CURRENT_VERSION=$(build_version_string "$PERIOD" "$MAJOR" "$MINOR" "$PATCH")
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
