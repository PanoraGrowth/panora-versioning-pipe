#!/bin/sh
# =============================================================================
# generate-changelog-per-folder.sh - Generate per-folder CHANGELOGs from scope
# =============================================================================
# Requires: commits.format: "conventional" and changelog.per_folder.enabled: true
# Maps commit scope to folder and generates CHANGELOG in that folder.
# =============================================================================

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
ROOT_FOLDERS=$(get_per_folder_root_folders)
FOLDER_PATTERN=$(get_per_folder_pattern)
SCOPE_MATCHING=$(get_per_folder_scope_matching)
TIMEZONE=$(get_timezone)
COMMIT_URL_BASE=$(get_commit_url)
IGNORE_PATTERN=$(get_ignore_patterns_regex)

if [ -z "$ROOT_FOLDERS" ]; then
    log_warn "No root_folders configured for per-folder changelogs. Skipping."
    exit 0
fi

log_info "Root folders: $ROOT_FOLDERS"
log_info "Folder pattern: ${FOLDER_PATTERN:-'(none)'}"
log_info "Scope matching: $SCOPE_MATCHING"
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
# Get ALL commits (excluding ignored patterns)
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
# Format date
# =============================================================================
export TZ="$TIMEZONE"
CHANGELOG_DATE=$(date +%Y-%m-%d)

# =============================================================================
# Process each commit and map to folder
# =============================================================================
MODIFIED_CHANGELOGS=""

echo "$COMMITS" | while IFS='|' read -r commit_hash commit_author commit_msg; do
    # Extract scope from commit message
    scope=$(extract_scope_from_commit "$commit_msg")

    if [ -z "$scope" ]; then
        log_info "No scope in commit: $commit_msg (skipping per-folder)"
        continue
    fi

    # Find matching folder
    target_folder=$(find_folder_for_scope "$scope" "$ROOT_FOLDERS" "$FOLDER_PATTERN" "$SCOPE_MATCHING")

    if [ -z "$target_folder" ]; then
        log_warn "No folder found for scope '$scope' in commit: $commit_msg"
        continue
    fi

    # Remove trailing slash
    target_folder=$(echo "$target_folder" | sed 's|/$||')

    log_info "Scope '$scope' -> $(basename "$target_folder")/CHANGELOG.md"

    # Build CHANGELOG entry
    short_hash=$(git log -1 "$commit_hash" --pretty=format:"%h")

    # Extract commit type and message (remove scope)
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
        # Create new CHANGELOG with version header
        echo "# Changelog

---

## ${NEXT_VERSION} - ${CHANGELOG_DATE}

${ENTRY}

" > "$FOLDER_CHANGELOG"
    else
        # Check if this version section already exists
        if grep -q "^## ${NEXT_VERSION}" "$FOLDER_CHANGELOG"; then
            # Append to existing version section (before the next --- or ## or end)
            # Use a temp file to insert after the version header
            TEMP_FILE=$(mktemp)
            awk -v version="## ${NEXT_VERSION}" -v entry="$ENTRY" '
                $0 == version { print; found=1; next }
                found && /^$/ { print entry; print ""; found=0 }
                { print }
            ' "$FOLDER_CHANGELOG" > "$TEMP_FILE"
            mv "$TEMP_FILE" "$FOLDER_CHANGELOG"
        else
            # Append new version section at the end
            echo "
## ${NEXT_VERSION} - ${CHANGELOG_DATE}

${ENTRY}

" >> "$FOLDER_CHANGELOG"
        fi
    fi

    # Track modified changelogs for git add
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
    log_info "No per-folder CHANGELOGs updated (no scoped commits found)"
fi
