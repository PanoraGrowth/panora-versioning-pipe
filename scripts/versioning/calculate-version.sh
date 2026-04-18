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
EPOCH_INITIAL=$(get_component_initial "epoch" "0")
MAJOR_INITIAL=$(get_component_initial "major" "0")
PATCH_INITIAL=$(get_component_initial "patch" "0")
HOTFIX_COUNTER_INITIAL=$(get_component_initial "hotfix_counter" "0")

# Build bump patterns from config
MAJOR_PATTERN=$(build_bump_pattern "major")
MINOR_PATTERN=$(build_bump_pattern "minor")
PATCH_PATTERN=$(build_bump_pattern "patch")

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
# Ticket 055: namespace filter so that epoch.initial / major.initial values are
# respected even when the repo already has tags matching TAG_PATTERN. Without
# this filter, `initial` was silently ignored whenever any tag existed, breaking
# migrations, epoch rotations, and namespace isolation.
INITIAL_PREFIX=$(build_initial_prefix_regex "$EPOCH_INITIAL" "$MAJOR_INITIAL")
LATEST_TAG=$(git tag --sort=-v:refname | \
    grep -E "$TAG_PATTERN" | \
    grep -E "$INITIAL_PREFIX" | head -n 1 || echo "")

# Save latest tag for other scripts (e.g. CHANGELOG_BASE_REF)
write_state "/tmp/latest_tag.txt" "${LATEST_TAG:-}"

if [ -z "$LATEST_TAG" ]; then
    log_info "No version tags found, starting from initial values"
    EPOCH=$EPOCH_INITIAL
    MAJOR=$MAJOR_INITIAL
    PATCH=$PATCH_INITIAL
    HOTFIX_COUNTER=$HOTFIX_COUNTER_INITIAL
else
    log_info "Latest tag: $LATEST_TAG"
    VERSION=$(parse_tag_to_version "$LATEST_TAG")
    parse_version_components "$VERSION"
    EPOCH=$PARSED_EPOCH
    MAJOR=$PARSED_MAJOR
    PATCH=$PARSED_PATCH
    HOTFIX_COUNTER=$PARSED_HOTFIX_COUNTER
    CURRENT_VER=$(build_version_string "$EPOCH" "$MAJOR" "$PATCH" "$HOTFIX_COUNTER")
    log_info "Current version: ${CURRENT_VER}"
    # Ticket 055: observability — progression components (patch, hotfix_counter)
    # are cold-start-only. When tags exist in the namespace, their `initial` is
    # ignored (progression continues from the latest tag). Log only when set
    # non-default, to avoid noise for consumers who never touched these.
    if [ "$PATCH_INITIAL" != "0" ]; then
        log_info "Note: version.components.patch.initial=${PATCH_INITIAL} is ignored (tags exist in namespace; patch progresses from latest tag)."
    fi
    if [ "$HOTFIX_COUNTER_INITIAL" != "0" ]; then
        log_info "Note: version.components.hotfix_counter.initial=${HOTFIX_COUNTER_INITIAL} is ignored (tags exist in namespace; hotfix_counter progresses from latest tag)."
    fi
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

# Select the commit that drives the bump:
#   changelog.mode=last_commit → last commit only (backward-compatible default)
#   changelog.mode=full        → scan all commits, pick the highest-ranked bump
#
# Rank: major(3) > minor(2) > patch(1) > timestamp_only(0)
# Coupling is intentional: if you care about all commits for the changelog,
# you also want the strongest bump signal from those same commits.
if is_full_changelog_mode; then
    BUMP_RANK=0
    WINNING_COMMIT=""
    while IFS= read -r _commit; do
        [ -z "$_commit" ] && continue
        if [ -n "$MAJOR_PATTERN" ] && echo "$_commit" | grep -qE "$MAJOR_PATTERN"; then
            _rank=3
        elif [ -n "$MINOR_PATTERN" ] && echo "$_commit" | grep -qE "$MINOR_PATTERN"; then
            _rank=2
        elif [ -n "$PATCH_PATTERN" ] && echo "$_commit" | grep -qE "$PATCH_PATTERN"; then
            _rank=1
        else
            _rank=0
        fi
        if [ "$_rank" -gt "$BUMP_RANK" ]; then
            BUMP_RANK=$_rank
            WINNING_COMMIT=$_commit
        fi
        [ "$BUMP_RANK" -eq 3 ] && break
    done <<EOF
$COMMITS
EOF
    [ -z "$WINNING_COMMIT" ] && WINNING_COMMIT=$(echo "$COMMITS" | head -n 1)
    LAST_COMMIT=$WINNING_COMMIT
    log_info "Strategy: highest-wins (changelog.mode=full) — winning commit: $LAST_COMMIT"
else
    LAST_COMMIT=$(echo "$COMMITS" | head -n 1)
    log_info "Strategy: last-commit (changelog.mode=last_commit) — last commit: $LAST_COMMIT"
fi
echo ""

# =============================================================================
# Detect bump type
# =============================================================================
# Hotfix scenario + hotfix_counter.enabled=true → bump HOTFIX_COUNTER, produce .N tag.
# Hotfix scenario + hotfix_counter.enabled=false → NO-OP: skip tag creation entirely and
#   emit a 3-line INFO log explaining why. The consumer opted out of the hotfix_counter
#   component explicitly, so honoring that opt-out is the expected behavior.
# Non-hotfix scenarios → fall through to commit-driven detection (last or highest, per above).
BUMP_TYPE="timestamp_only"

if [ "$SCENARIO" = "hotfix" ]; then
    if is_component_enabled "hotfix_counter"; then
        BUMP_TYPE="patch"
        HOTFIX_COUNTER=$((HOTFIX_COUNTER + 1))
        log_info "Detected: PATCH bump (hotfix scenario)"
    else
        log_info "Hotfix commit detected (\"$LAST_COMMIT\") but version.components.hotfix_counter.enabled is false."
        log_info "Skipping tag creation (consumer opted out of hotfix_counter component)."
        log_info "To enable hotfix tags, set version.components.hotfix_counter.enabled: true in your .versioning.yml."
        write_state "/tmp/next_version.txt" ""
        write_state "/tmp/bump_type.txt" ""
        exit 0
    fi
elif [ -n "$MAJOR_PATTERN" ] && echo "$LAST_COMMIT" | grep -qE "$MAJOR_PATTERN"; then
    BUMP_TYPE="major"
    MAJOR=$((MAJOR + 1))
    PATCH=0
    HOTFIX_COUNTER=0
    log_info "Detected: MAJOR bump"
elif [ -n "$MINOR_PATTERN" ] && echo "$LAST_COMMIT" | grep -qE "$MINOR_PATTERN"; then
    # NOTE: MINOR_PATTERN matches feat/feature (bump: minor). Post-042, this bumps
    # the PATCH var (3rd slot, renamed from MINOR). HOTFIX_COUNTER (4th slot) resets.
    BUMP_TYPE="minor"
    PATCH=$((PATCH + 1))
    HOTFIX_COUNTER=0
    log_info "Detected: MINOR bump"
elif [ -n "$PATCH_PATTERN" ] && echo "$LAST_COMMIT" | grep -qE "$PATCH_PATTERN"; then
    # NOTE: PATCH_PATTERN matches fix/security/revert/perf and bumps the PATCH
    # var (3rd slot, named `patch` post-042). NOT related to HOTFIX_COUNTER,
    # which is bumped only by SCENARIO=hotfix routing above.
    BUMP_TYPE="patch"
    PATCH=$((PATCH + 1))
    HOTFIX_COUNTER=0
    log_info "Detected: PATCH bump"
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
CURRENT_VERSION=$(build_version_string "$EPOCH" "$MAJOR" "$PATCH" "$HOTFIX_COUNTER")
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
