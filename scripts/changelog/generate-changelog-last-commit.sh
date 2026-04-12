#!/bin/sh
# =============================================================================
# generate-changelog-last-commit.sh - Generate root CHANGELOG entry
# =============================================================================
# Supports two modes:
#   - last_commit: only the last commit (default, backward compatible)
#   - full: all commits since last tag
# Excludes commits already routed to per-folder CHANGELOGs via /tmp/routed_commits.txt
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/../lib/common.sh"
. "${SCRIPT_DIR}/../lib/config-parser.sh"

# Load scenario
load_env "/tmp/scenario.env"

# Generate the root CHANGELOG for development releases AND hotfix scenarios.
# Hotfix releases reuse this generator (the marker is injected into the header
# below) so the entire release flow — dev or hotfix — goes through a single path.
case "$SCENARIO" in
    development_release|hotfix) ;;
    *) exit 0 ;;
esac

# Append a "(Hotfix)" marker to the version header when the release is a
# hotfix. Dev releases render unchanged.
HEADER_SUFFIX=""
if [ "$SCENARIO" = "hotfix" ]; then
    HEADER_SUFFIX=" (Hotfix)"
fi

log_section "GENERATING CHANGELOG"

# =============================================================================
# Load configuration
# =============================================================================
CHANGELOG_FILE=$(get_changelog_file)
CHANGELOG_TITLE=$(get_changelog_title)
CHANGELOG_MODE=$(get_changelog_mode)
TIMEZONE=$(get_timezone)
COMMIT_URL_BASE=$(get_commit_url)
TICKET_URL_BASE=$(get_ticket_url)
TICKET_LINK_LABEL=$(get_ticket_link_label)
IGNORE_PATTERN=$(get_ignore_patterns_regex)

log_info "Mode: $CHANGELOG_MODE"

# =============================================================================
# Read calculated version
# =============================================================================
if [ ! -f "/tmp/next_version.txt" ]; then
    log_error "Version file not found. Run calculate-version.sh first."
    exit 1
fi

NEXT_VERSION=$(cat /tmp/next_version.txt)
log_info "Version: $NEXT_VERSION"
echo ""

# =============================================================================
# Get commits (excluding ignored patterns)
# =============================================================================
if [ -z "${CHANGELOG_BASE_REF:-}" ]; then
    log_info "No base ref set (first run) — using all commits"
    GIT_RANGE="HEAD"
else
    GIT_RANGE="${CHANGELOG_BASE_REF}..HEAD"
fi

ALL_COMMITS=$(git log $GIT_RANGE \
    --no-merges \
    --pretty=format:"%H|%an|%s")

# Filter ignored patterns against the commit SUBJECT (3rd field), not the full line.
# Patterns like ^Revert are anchored to the start of the subject, so grep on the
# full "hash|author|subject" line would never match.
if [ -n "$IGNORE_PATTERN" ] && [ -n "$ALL_COMMITS" ]; then
    ALL_COMMITS=$(echo "$ALL_COMMITS" | awk -F'|' -v pat="$IGNORE_PATTERN" '$3 !~ pat' || true)
fi

if [ -z "$ALL_COMMITS" ]; then
    log_info "No valid commits found for CHANGELOG"
    exit 0
fi

# =============================================================================
# Exclude routed commits (already in per-folder CHANGELOGs)
# =============================================================================
ROUTED_COMMITS=""
if [ -f "/tmp/routed_commits.txt" ] && [ -s "/tmp/routed_commits.txt" ]; then
    ROUTED_COMMITS=$(cat /tmp/routed_commits.txt)
    ROUTED_COUNT=$(echo "$ROUTED_COMMITS" | wc -l | tr -d ' ')
    log_info "Excluding $ROUTED_COUNT commit(s) already routed to per-folder CHANGELOGs"
fi

# Filter out routed commits
if [ -n "$ROUTED_COMMITS" ]; then
    FILTERED_COMMITS=""
    echo "$ALL_COMMITS" | while IFS='|' read -r hash author msg; do
        if ! echo "$ROUTED_COMMITS" | grep -q "$hash"; then
            echo "${hash}|${author}|${msg}"
        fi
    done > /tmp/filtered_commits.txt
    FILTERED_COMMITS=$(cat /tmp/filtered_commits.txt 2>/dev/null || true)
    rm -f /tmp/filtered_commits.txt
else
    FILTERED_COMMITS="$ALL_COMMITS"
fi

# =============================================================================
# Determine which commits to include based on mode
# =============================================================================
if [ "$CHANGELOG_MODE" = "full" ]; then
    COMMITS_TO_INCLUDE="$FILTERED_COMMITS"
else
    # last_commit mode: only the LAST commit from ALL commits (not filtered)
    # If the last commit was already routed to per-folder, nothing goes to root
    LAST_ONLY=$(echo "$ALL_COMMITS" | head -n 1)
    LAST_HASH=$(echo "$LAST_ONLY" | cut -d'|' -f1)
    if [ -n "$ROUTED_COMMITS" ] && echo "$ROUTED_COMMITS" | grep -q "$LAST_HASH"; then
        COMMITS_TO_INCLUDE=""
    else
        COMMITS_TO_INCLUDE="$LAST_ONLY"
    fi
fi

if [ -z "$COMMITS_TO_INCLUDE" ]; then
    log_info "All commits routed to per-folder CHANGELOGs — no root CHANGELOG entry needed"
    exit 0
fi

# =============================================================================
# Format date
# =============================================================================
export TZ="$TIMEZONE"
CHANGELOG_DATE=$(date +%Y-%m-%d)

# =============================================================================
# Build CHANGELOG entry
# =============================================================================
CHANGELOG_ENTRY="## ${NEXT_VERSION} - ${CHANGELOG_DATE}

"

echo "$COMMITS_TO_INCLUDE" | while IFS='|' read -r commit_hash commit_author commit_msg; do
    [ -z "$commit_hash" ] && continue

    COMMIT_SHORT_HASH=$(git log -1 "$commit_hash" --pretty=format:"%h")

    # Extract ticket ID from commit message (if prefixes configured)
    TICKET_ID=""
    if has_ticket_prefixes; then
        TICKET_PREFIXES=$(get_ticket_prefixes_pattern)
        TICKET_ID=$(echo "$commit_msg" | grep -oE "(${TICKET_PREFIXES})-[0-9]+" | head -1)
    fi

    # Build emoji prefix if enabled
    EMOJI_PREFIX=""
    if use_changelog_emojis; then
        COMMIT_TYPE=$(echo "$commit_msg" | sed -n 's/^\([a-z]*\).*/\1/p')
        EMOJI=$(get_commit_type_emoji "$COMMIT_TYPE")
        if [ -n "$EMOJI" ] && [ "$EMOJI" != "null" ]; then
            EMOJI_PREFIX="${EMOJI} "
        fi
    fi

    # Add commit line
    if [ -n "$TICKET_ID" ]; then
        echo "- ${EMOJI_PREFIX}**${TICKET_ID}** - ${commit_msg#*- }"
    else
        echo "- ${EMOJI_PREFIX}${commit_msg}"
    fi

    # Add author (if configured)
    if include_author; then
        echo "  - _${commit_author}_"
    fi

    # Add ticket link (if configured and ticket exists)
    if include_ticket_link && [ -n "$TICKET_URL_BASE" ] && [ -n "$TICKET_ID" ]; then
        echo "  - [${TICKET_LINK_LABEL}](${TICKET_URL_BASE}/${TICKET_ID})"
    fi

    # Add commit link (if configured)
    if include_commit_link && [ -n "$COMMIT_URL_BASE" ]; then
        echo "  - [Commit: ${COMMIT_SHORT_HASH}](${COMMIT_URL_BASE}/${commit_hash})"
    fi

done > /tmp/changelog_entries.txt

# Read entries back (avoids subshell variable loss)
ENTRIES=$(cat /tmp/changelog_entries.txt 2>/dev/null || true)
rm -f /tmp/changelog_entries.txt

if [ -z "$ENTRIES" ]; then
    log_info "No entries to write to root CHANGELOG"
    exit 0
fi

CHANGELOG_ENTRY="## ${NEXT_VERSION}${HEADER_SUFFIX} - ${CHANGELOG_DATE}

${ENTRIES}

"

log_info "CHANGELOG entry:"
echo "$CHANGELOG_ENTRY"

# =============================================================================
# Update CHANGELOG (APPEND to end)
# =============================================================================
if [ ! -f "$CHANGELOG_FILE" ]; then
    log_info "Creating new $CHANGELOG_FILE"
    echo "# $CHANGELOG_TITLE

---

${CHANGELOG_ENTRY}" > "$CHANGELOG_FILE"
else
    log_info "Updating existing $CHANGELOG_FILE (appending to end)"
    echo "${CHANGELOG_ENTRY}" >> "$CHANGELOG_FILE"
fi

log_success "$CHANGELOG_FILE updated successfully (appended to end)"
log_info ""
log_info "Note: New entries are added at the END of CHANGELOG"
log_info "This prevents merge conflicts with main/pre-production"
