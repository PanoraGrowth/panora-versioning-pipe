#!/bin/sh
# =============================================================================
# generate-changelog-last-commit.sh - Generate CHANGELOG entry for development
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/../lib/common.sh"
. "${SCRIPT_DIR}/../lib/config-parser.sh"

# Load scenario
load_env "/tmp/scenario.env"

# Only generate changelog for development releases
if [ "$SCENARIO" != "development_release" ]; then
    exit 0
fi

log_section "GENERATING CHANGELOG (LAST COMMIT ONLY)"

# =============================================================================
# Load configuration
# =============================================================================
CHANGELOG_FILE=$(get_changelog_file)
CHANGELOG_TITLE=$(get_changelog_title)
TIMEZONE=$(get_timezone)
COMMIT_URL_BASE=$(get_commit_url)
TICKET_URL_BASE=$(get_ticket_url)
TICKET_LINK_LABEL=$(get_ticket_link_label)
IGNORE_PATTERN=$(get_ignore_patterns_regex)

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
# Get LAST commit (excluding ignored patterns)
# =============================================================================
if [ -z "${CHANGELOG_BASE_REF:-}" ]; then
    log_info "No base ref set (first run) — using all commits"
    GIT_RANGE="HEAD"
else
    GIT_RANGE="${CHANGELOG_BASE_REF}..HEAD"
fi

if [ -n "$IGNORE_PATTERN" ]; then
    COMMITS=$(git log $GIT_RANGE \
        --no-merges \
        --pretty=format:"%s" | \
        grep -vE "$IGNORE_PATTERN" || true)
else
    COMMITS=$(git log $GIT_RANGE \
        --no-merges \
        --pretty=format:"%s")
fi

LAST_COMMIT=$(echo "$COMMITS" | head -n 1)

if [ -z "$LAST_COMMIT" ]; then
    log_error "No valid commits found for CHANGELOG"
    exit 1
fi

# =============================================================================
# Extract commit metadata
# =============================================================================
LAST_COMMIT_HASH=$(git log $GIT_RANGE \
    --no-merges \
    --pretty=format:"%H" | head -n 1)

COMMIT_SHORT_HASH=$(git log -1 $LAST_COMMIT_HASH --pretty=format:"%h")
COMMIT_AUTHOR=$(git log -1 $LAST_COMMIT_HASH --pretty=format:"%an")
COMMIT_MESSAGE=$LAST_COMMIT

log_info "Last commit:"
log_info "  Hash: $COMMIT_SHORT_HASH"
log_info "  Author: $COMMIT_AUTHOR"
log_info "  Message: $COMMIT_MESSAGE"
echo ""

# Extract ticket ID from commit message (if prefixes configured)
TICKET_ID=""
if has_ticket_prefixes; then
    TICKET_PREFIXES=$(get_ticket_prefixes_pattern)
    TICKET_ID=$(echo "$COMMIT_MESSAGE" | grep -oE "(${TICKET_PREFIXES})-[0-9]+" | head -1)
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

# Add commit line (with or without ticket)
if [ -n "$TICKET_ID" ]; then
    CHANGELOG_ENTRY="${CHANGELOG_ENTRY}- **${TICKET_ID}** - ${COMMIT_MESSAGE#*- }
"
else
    CHANGELOG_ENTRY="${CHANGELOG_ENTRY}- ${COMMIT_MESSAGE}
"
fi

# Add author (if configured)
if include_author; then
    CHANGELOG_ENTRY="${CHANGELOG_ENTRY}  - _${COMMIT_AUTHOR}_
"
fi

# Add ticket link (if configured and ticket exists)
if include_ticket_link && [ -n "$TICKET_URL_BASE" ] && [ -n "$TICKET_ID" ]; then
    CHANGELOG_ENTRY="${CHANGELOG_ENTRY}  - [${TICKET_LINK_LABEL}](${TICKET_URL_BASE}/${TICKET_ID})
"
fi

# Add commit link (if configured)
if include_commit_link && [ -n "$COMMIT_URL_BASE" ]; then
    CHANGELOG_ENTRY="${CHANGELOG_ENTRY}  - [Commit: ${COMMIT_SHORT_HASH}](${COMMIT_URL_BASE}/${LAST_COMMIT_HASH})
"
fi

# Add trailing newline
CHANGELOG_ENTRY="${CHANGELOG_ENTRY}
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
