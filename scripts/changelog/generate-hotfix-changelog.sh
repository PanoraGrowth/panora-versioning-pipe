#!/bin/sh
# =============================================================================
# generate-hotfix-changelog.sh - Generate changelog entry for hotfix
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/../lib/common.sh"
. "${SCRIPT_DIR}/../lib/config-parser.sh"

# Load scenario
load_env "/tmp/scenario.env"

# Only generate for hotfix scenarios
case "$SCENARIO" in
    hotfix_to_main|hotfix_to_preprod)
        ;;
    *)
        exit 0
        ;;
esac

log_section "GENERATING HOTFIX CHANGELOG"

# =============================================================================
# Load configuration
# =============================================================================
CHANGELOG_FILE=$(get_changelog_file)
CHANGELOG_TITLE=$(get_changelog_title)
HOTFIX_HEADER=$(get_hotfix_changelog_header)
TIMEZONE=$(get_timezone)
COMMIT_URL_BASE=$(get_commit_url)
TICKET_URL_BASE=$(get_ticket_url)
TICKET_LINK_LABEL=$(get_ticket_link_label)
IGNORE_PATTERN=$(get_ignore_patterns_regex)

# =============================================================================
# Get last commit info
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
COMMIT_HASH=$(git log -1 --pretty=format:"%h")
COMMIT_FULL_HASH=$(git log -1 --pretty=format:"%H")
AUTHOR=$(git log -1 --pretty=format:"%an")

# Extract ticket ID (if prefixes configured)
TICKET_ID=""
if has_ticket_prefixes; then
    TICKET_PREFIXES=$(get_ticket_prefixes_pattern)
    TICKET_ID=$(echo "$LAST_COMMIT" | grep -oE "(${TICKET_PREFIXES})-[0-9]+" | head -1)
fi

# Get date in configured timezone
export TZ="$TIMEZONE"
COMMIT_DATE=$(date "+%Y-%m-%d")

log_info "Last commit: $LAST_COMMIT"
log_info "Ticket: ${TICKET_ID:-N/A}"
log_info "Author: $AUTHOR"
log_info "Date: $COMMIT_DATE"
echo ""

# =============================================================================
# Build changelog entry
# =============================================================================
CHANGELOG_ENTRY="## ${HOTFIX_HEADER} - ${COMMIT_DATE}

"

# Add commit line (with or without ticket)
if [ -n "$TICKET_ID" ]; then
    CHANGELOG_ENTRY="${CHANGELOG_ENTRY}- **${TICKET_ID}** - ${LAST_COMMIT#*- }
"
else
    CHANGELOG_ENTRY="${CHANGELOG_ENTRY}- ${LAST_COMMIT}
"
fi

# Add author (if configured)
if include_author; then
    CHANGELOG_ENTRY="${CHANGELOG_ENTRY}  - _${AUTHOR}_
"
fi

# Add ticket link (if configured and ticket exists)
if include_ticket_link && [ -n "$TICKET_URL_BASE" ] && [ -n "$TICKET_ID" ]; then
    CHANGELOG_ENTRY="${CHANGELOG_ENTRY}  - [${TICKET_LINK_LABEL}](${TICKET_URL_BASE}/${TICKET_ID})
"
fi

# Add commit link (if configured)
if include_commit_link && [ -n "$COMMIT_URL_BASE" ]; then
    CHANGELOG_ENTRY="${CHANGELOG_ENTRY}  - [Commit: ${COMMIT_HASH}](${COMMIT_URL_BASE}/${COMMIT_FULL_HASH})
"
fi

# Add trailing newline
CHANGELOG_ENTRY="${CHANGELOG_ENTRY}
"

log_info "=== CHANGELOG ENTRY ==="
echo "$CHANGELOG_ENTRY"
log_info "======================="
echo ""

# =============================================================================
# Append to CHANGELOG
# =============================================================================
if [ ! -f "$CHANGELOG_FILE" ]; then
    echo "# ${CHANGELOG_TITLE}

---

${CHANGELOG_ENTRY}" > "$CHANGELOG_FILE"
    log_success "CHANGELOG created with hotfix entry"
else
    echo "${CHANGELOG_ENTRY}" >> "$CHANGELOG_FILE"
    log_success "Hotfix entry appended to CHANGELOG"
fi

echo ""
log_info "=== CHANGELOG PREVIEW (last 20 lines) ==="
tail -20 "$CHANGELOG_FILE"
