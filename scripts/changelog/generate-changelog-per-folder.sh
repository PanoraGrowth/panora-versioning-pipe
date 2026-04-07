#!/bin/sh
# =============================================================================
# generate-changelog-per-folder.sh - Generate per-folder CHANGELOGs from scope
# =============================================================================
# Routes commits to folder-specific CHANGELOGs based on scope matching,
# subfolder discovery, and file_path fallback.
# Writes /tmp/routed_commits.txt for the root changelog to exclude.
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/../lib/common.sh"
. "${SCRIPT_DIR}/../lib/config-parser.sh"

# Load scenario
load_env "/tmp/scenario.env"

# Only generate for development releases
if [ "$SCENARIO" != "development_release" ]; then
    exit 0
fi

# Only run if per-folder changelogs are enabled
if ! is_per_folder_changelog_enabled; then
    exit 0
fi

# Requires conventional commits format
if ! is_conventional_commits; then
    log_warn "Per-folder changelogs require commits.format: 'conventional'. Skipping."
    exit 0
fi

log_section "GENERATING PER-FOLDER CHANGELOGS"

# =============================================================================
# Load configuration
# =============================================================================
FOLDERS=$(get_per_folder_folders)
FOLDER_PATTERN=$(get_per_folder_pattern)
SCOPE_MATCHING=$(get_per_folder_scope_matching)
FALLBACK=$(get_per_folder_fallback)
CHANGELOG_MODE=$(get_changelog_mode)
TIMEZONE=$(get_timezone)
COMMIT_URL_BASE=$(get_commit_url)
IGNORE_PATTERN=$(get_ignore_patterns_regex)

if [ -z "$FOLDERS" ]; then
    log_warn "No folders configured for per-folder changelogs. Skipping."
    exit 0
fi

log_info "Folders: $FOLDERS"
log_info "Folder pattern: ${FOLDER_PATTERN:-'(none)'}"
log_info "Scope matching: $SCOPE_MATCHING"
log_info "Fallback: $FALLBACK"
log_info "Mode: $CHANGELOG_MODE"
echo ""

# =============================================================================
# Read calculated version
# =============================================================================
if [ ! -f "/tmp/next_version.txt" ]; then
    log_error "Version file not found. Run calculate-version.sh first."
    exit 1
fi

NEXT_VERSION=$(cat /tmp/next_version.txt)

# =============================================================================
# Initialize routed commits tracking
# =============================================================================
> /tmp/routed_commits.txt

# =============================================================================
# Get commits
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
        --pretty=format:"%H|%an|%s" | \
        grep -vE "$IGNORE_PATTERN" || true)
else
    COMMITS=$(git log $GIT_RANGE \
        --no-merges \
        --pretty=format:"%H|%an|%s")
fi

if [ -z "$COMMITS" ]; then
    log_info "No commits to process for per-folder changelogs"
    exit 0
fi

# =============================================================================
# Determine which commits to process based on mode
# =============================================================================
if [ "$CHANGELOG_MODE" = "full" ]; then
    COMMITS_TO_PROCESS="$COMMITS"
else
    # last_commit mode: only process the last (most recent) commit
    COMMITS_TO_PROCESS=$(echo "$COMMITS" | head -n 1)
fi

# =============================================================================
# Format date
# =============================================================================
export TZ="$TIMEZONE"
CHANGELOG_DATE=$(date +%Y-%m-%d)

# =============================================================================
# Process each commit and route to folder
# =============================================================================
# Use a temp file to avoid subshell variable scoping issues
TEMP_ROUTING="/tmp/per_folder_routing.txt"
> "$TEMP_ROUTING"

echo "$COMMITS_TO_PROCESS" | while IFS='|' read -r commit_hash commit_author commit_msg; do
    [ -z "$commit_hash" ] && continue

    # Extract scope from commit message
    scope=$(extract_scope_from_commit "$commit_msg")

    # Step 1: No scope → skip (goes to root)
    if [ -z "$scope" ]; then
        log_info "No scope: $commit_msg → root CHANGELOG"
        continue
    fi

    # Step 2+3: Try scope match + subfolder discovery
    target_folder=$(find_folder_for_scope "$scope" "$FOLDERS" "$FOLDER_PATTERN" "$SCOPE_MATCHING")

    # Step 4: If no match and fallback is file_path, try by modified files
    if [ -z "$target_folder" ] && [ "$FALLBACK" = "file_path" ]; then
        target_folder=$(find_folder_by_file_path "$commit_hash" "$FOLDERS")
        if [ -n "$target_folder" ]; then
            log_info "Scope '$scope' → fallback file_path → $(basename "$target_folder")/"
        fi
    fi

    # No match at all → skip (goes to root)
    if [ -z "$target_folder" ]; then
        log_info "Scope '$scope' no match: $commit_msg → root CHANGELOG"
        continue
    fi

    # Remove trailing slash if any
    target_folder=$(echo "$target_folder" | sed 's|/$||')

    log_info "Scope '$scope' → $(echo "$target_folder" | sed "s|${REPO_ROOT}/||")/CHANGELOG.md"

    # Mark commit as routed
    echo "$commit_hash" >> /tmp/routed_commits.txt

    # Build CHANGELOG entry
    short_hash=$(git log -1 "$commit_hash" --pretty=format:"%h")
    commit_type=$(echo "$commit_msg" | sed -n 's/^\([a-z]*\)(.*/\1/p')
    clean_msg=$(echo "$commit_msg" | sed 's/^[a-z]*([^)]*): //')
    if [ -z "$clean_msg" ]; then
        clean_msg=$(echo "$commit_msg" | sed 's/^[a-z]*: //')
    fi

    ENTRY="- **${commit_type}**: ${clean_msg}
  _${commit_author}_"

    if [ -n "$COMMIT_URL_BASE" ]; then
        ENTRY="${ENTRY}
  [Commit: ${short_hash}](${COMMIT_URL_BASE}/${commit_hash})"
    fi

    # Write to folder CHANGELOG
    FOLDER_CHANGELOG="${target_folder}/CHANGELOG.md"

    if [ ! -f "$FOLDER_CHANGELOG" ]; then
        echo "# Changelog

---

## ${NEXT_VERSION} - ${CHANGELOG_DATE}

${ENTRY}

" > "$FOLDER_CHANGELOG"
    else
        if grep -q "^## ${NEXT_VERSION}" "$FOLDER_CHANGELOG"; then
            TEMP_FILE=$(mktemp)
            awk -v version="## ${NEXT_VERSION}" -v entry="$ENTRY" '
                index($0, version) == 1 { print; found=1; next }
                found && /^$/ { print entry; print ""; found=0 }
                { print }
            ' "$FOLDER_CHANGELOG" > "$TEMP_FILE"
            mv "$TEMP_FILE" "$FOLDER_CHANGELOG"
        else
            echo "
## ${NEXT_VERSION} - ${CHANGELOG_DATE}

${ENTRY}

" >> "$FOLDER_CHANGELOG"
        fi
    fi

    # Track for git add
    echo "$FOLDER_CHANGELOG" >> /tmp/per_folder_changelogs.txt

done

# =============================================================================
# Summary
# =============================================================================
if [ -f "/tmp/per_folder_changelogs.txt" ]; then
    UNIQUE_CHANGELOGS=$(sort -u /tmp/per_folder_changelogs.txt)
    COUNT=$(echo "$UNIQUE_CHANGELOGS" | wc -l | tr -d ' ')
    log_success "Updated $COUNT per-folder CHANGELOG(s)"
    echo "$UNIQUE_CHANGELOGS" | while IFS= read -r cl; do
        log_info "  - $cl"
    done
else
    log_info "No per-folder CHANGELOGs updated (no scoped commits matched)"
fi

if [ -f "/tmp/routed_commits.txt" ] && [ -s "/tmp/routed_commits.txt" ]; then
    ROUTED_COUNT=$(wc -l < /tmp/routed_commits.txt | tr -d ' ')
    log_info "$ROUTED_COUNT commit(s) routed to per-folder CHANGELOGs (excluded from root)"
fi
