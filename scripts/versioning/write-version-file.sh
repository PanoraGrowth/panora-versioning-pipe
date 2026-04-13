#!/bin/sh
# shellcheck shell=ash
set -e
# =============================================================================
# write-version-file.sh - Write version to configured file(s)
# =============================================================================
# Supports three modes:
#   - yaml: Write version to a YAML file
#   - json: Write version to a JSON file
#   - regex: Use sed to replace pattern in multiple files
#
# Monorepo support:
#   When 'groups' are configured, only files in matched groups are updated
#   based on which files were changed in the PR.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/config-parser.sh
. "${SCRIPT_DIR}/../lib/config-parser.sh"

# Find repository root
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# =============================================================================
# Helper: Get changed files in this PR
# =============================================================================
get_changed_files() {
    # Using git diff against the target branch
    local target_branch="${VERSIONING_TARGET_BRANCH:-development}"

    # Fetch the target branch if not available
    git fetch origin "$target_branch" 2>/dev/null || true

    # Get changed files (excluding the versioning commit itself)
    git diff --name-only "origin/${target_branch}...HEAD" 2>/dev/null | \
        grep -v "CHANGELOG.md" | \
        grep -v "environment\.dev\.ts" | \
        grep -v "environment\.pre\.ts" | \
        grep -v "environment\.prod\.ts" || true
}

# =============================================================================
# Helper: Check if a file matches a glob pattern
# =============================================================================
matches_glob() {
    local file="$1"
    local pattern="$2"

    # Convert glob pattern to regex
    # ** matches any path, * matches any name
    local regex
    regex=$(echo "$pattern" | sed 's/\./\\./g' | sed 's/\*\*/DOUBLESTAR/g' | sed 's/\*/[^\/]*/g' | sed 's/DOUBLESTAR/.*/g')

    echo "$file" | grep -qE "^${regex}$"
}

# =============================================================================
# Helper: Check if any changed file matches any trigger path in a group
# =============================================================================
group_matches_changes() {
    local group_index="$1"
    local changed_files="$2"

    local trigger_paths
    trigger_paths=$(get_version_file_group_trigger_paths "$group_index")

    if [ -z "$trigger_paths" ]; then
        return 1
    fi

    echo "$changed_files" | while read -r changed_file; do
        if [ -z "$changed_file" ]; then
            continue
        fi

        echo "$trigger_paths" | while read -r pattern; do
            if [ -z "$pattern" ]; then
                continue
            fi

            if matches_glob "$changed_file" "$pattern"; then
                # Return success by creating a marker file
                touch /tmp/group_matched
                return 0
            fi
        done
    done

    # Check if marker was created
    if [ -f /tmp/group_matched ]; then
        rm -f /tmp/group_matched
        return 0
    fi

    return 1
}

# =============================================================================
# Helper: Get list of files to update based on groups
# Returns: file paths to stdout (one per line)
# Logs: all informational messages go to stderr
# =============================================================================
get_files_to_update_from_groups() {
    local changed_files
    changed_files=$(get_changed_files)
    local groups_count
    groups_count=$(get_version_file_groups_count)
    local update_all_groups="false"
    local matched_groups=""

    # All log messages go to stderr to avoid mixing with file output
    log_info "Analyzing changed files for group matching..." >&2
    echo "" >&2

    # Debug: show changed files
    if [ -n "$changed_files" ]; then
        log_info "Changed files in PR:" >&2
        echo "$changed_files" | while read -r f; do
            [ -n "$f" ] && echo "  - $f" >&2
        done
        echo "" >&2
    else
        log_warn "No changed files detected, will update all groups" >&2
        update_all_groups="true"
    fi

    # Check each group for matches
    local i=0
    while [ "$i" -lt "$groups_count" ]; do
        local group_name
        group_name=$(get_version_file_group_name "$i")

        if group_matches_changes "$i" "$changed_files"; then
            log_info "Group '$group_name' matches changed files" >&2
            matched_groups="${matched_groups}${i} "

            # Check if this group has update_all flag
            if is_version_file_group_update_all "$i"; then
                log_info "Group '$group_name' has update_all=true, will update all groups" >&2
                update_all_groups="true"
            fi
        fi

        i=$((i + 1))
    done

    # Check if any changed file didn't match any group
    if [ -n "$changed_files" ] && [ "$update_all_groups" = "false" ]; then
        echo "$changed_files" | while read -r changed_file; do
            if [ -z "$changed_file" ]; then
                continue
            fi

            local j=0
            while [ "$j" -lt "$groups_count" ]; do
                local trigger_paths
                trigger_paths=$(get_version_file_group_trigger_paths "$j")
                echo "$trigger_paths" | while read -r pattern; do
                    if [ -n "$pattern" ] && matches_glob "$changed_file" "$pattern"; then
                        touch /tmp/file_matched
                    fi
                done
                j=$((j + 1))
            done

            if [ -f /tmp/file_matched ]; then
                rm -f /tmp/file_matched
            else
                # File didn't match any group
                echo "$changed_file" >> /tmp/unmatched_files
            fi
        done

        if [ -f /tmp/unmatched_files ]; then
            local unmatched_behavior
            unmatched_behavior=$(get_unmatched_files_behavior)
            log_warn "Some files didn't match any group trigger_paths:" >&2
            cat /tmp/unmatched_files | while read -r f; do
                echo "  - $f" >&2
            done
            rm -f /tmp/unmatched_files

            case "$unmatched_behavior" in
                "update_all")
                    log_info "Behavior 'update_all': updating all groups" >&2
                    update_all_groups="true"
                    ;;
                "update_none")
                    log_info "Behavior 'update_none': only updating matched groups" >&2
                    ;;
                "error")
                    log_error "Behavior 'error': failing due to unmatched files" >&2
                    exit 1
                    ;;
            esac
            echo "" >&2
        fi
    fi

    # Collect files to update (only this goes to stdout)
    if [ "$update_all_groups" = "true" ]; then
        # Update all groups
        local i=0
        while [ "$i" -lt "$groups_count" ]; do
            get_version_file_group_files "$i"
            i=$((i + 1))
        done
    else
        # Update only matched groups
        for group_index in $matched_groups; do
            get_version_file_group_files "$group_index"
        done
    fi
}

# =============================================================================
# Check if feature is enabled
# =============================================================================
if ! is_version_file_enabled; then
    log_info "Version file feature is disabled, skipping"
    exit 0
fi

log_section "WRITING VERSION FILE"

# =============================================================================
# Get version from previous step
# =============================================================================
if [ ! -f /tmp/next_version.txt ]; then
    log_error "Version file not found. Run calculate-version.sh first."
    exit 1
fi

VERSION=$(cat /tmp/next_version.txt)
log_info "Version to write: $VERSION"
echo ""

# For json/yaml modes, store plain semver (strip tag_prefix_v if set).
# npm, package.json, changesets, semantic-release all require the
# `version` field without the `v` prefix. Regex mode is unaffected —
# consumers template {{VERSION}} in their replacement and can choose
# whether to emit the prefix themselves.
VERSION_PLAIN="$VERSION"
TAG_PREFIX=$(get_tag_prefix)
if [ -n "$TAG_PREFIX" ]; then
    VERSION_PLAIN="${VERSION#"$TAG_PREFIX"}"
fi

# =============================================================================
# Get configuration
# =============================================================================
FILE_TYPE=$(get_version_file_type)
log_info "Mode: $FILE_TYPE"

# Track modified files for git add
MODIFIED_FILES=""

# =============================================================================
# YAML Mode
# =============================================================================
write_yaml() {
    local file_path
    file_path="${REPO_ROOT}/$(get_version_file_path)"
    local key
    key=$(get_version_file_key)

    log_info "Writing to: $file_path"
    log_info "Key: $key"

    # Create or update YAML file
    if [ -f "$file_path" ]; then
        # Update existing file
        yq -i ".${key} = \"${VERSION_PLAIN}\"" "$file_path"
    else
        # Create new file
        mkdir -p "$(dirname "$file_path")"
        echo "${key}: \"${VERSION_PLAIN}\"" > "$file_path"
    fi

    MODIFIED_FILES="$file_path"
    log_success "Updated $file_path"
}

# =============================================================================
# JSON Mode
# =============================================================================
write_json() {
    local file_path
    file_path="${REPO_ROOT}/$(get_version_file_path)"
    local key
    key=$(get_version_file_key)

    log_info "Writing to: $file_path"
    log_info "Key: $key"

    # Create or update JSON file
    if [ -f "$file_path" ]; then
        # Update existing file using yq (can handle JSON too)
        yq -i -o=json ".${key} = \"${VERSION_PLAIN}\"" "$file_path"
    else
        # Create new file
        mkdir -p "$(dirname "$file_path")"
        echo "{\"${key}\": \"${VERSION_PLAIN}\"}" | yq -o=json > "$file_path"
    fi

    MODIFIED_FILES="$file_path"
    log_success "Updated $file_path"
}

# =============================================================================
# Regex Mode (for TypeScript, etc.)
# =============================================================================
write_regex() {
    local pattern
    pattern=$(get_version_file_pattern)
    local replacement
    replacement=$(get_version_file_replacement)

    if [ -z "$pattern" ]; then
        log_error "No pattern configured for regex mode"
        exit 1
    fi

    if [ -z "$replacement" ]; then
        log_error "No replacement configured for regex mode"
        exit 1
    fi

    # Replace {{VERSION}} placeholder with actual version
    replacement=$(echo "$replacement" | sed "s/{{VERSION}}/${VERSION}/g")

    log_info "Pattern: $pattern"
    log_info "Replacement: $replacement"
    echo ""

    # Determine which files to update
    local files_to_update=""

    if has_version_file_groups; then
        log_info "Groups configured - using monorepo mode"
        echo ""
        files_to_update=$(get_files_to_update_from_groups)
    else
        log_info "No groups configured - using legacy mode (all files)"
        files_to_update=$(get_version_files_list)
    fi

    if [ -z "$files_to_update" ]; then
        log_warn "No files to update"
        return
    fi

    echo ""
    log_info "Files to update:"

    # Process each file
    echo "$files_to_update" | while read -r file; do
        if [ -z "$file" ]; then
            continue
        fi

        local file_path="${REPO_ROOT}/${file}"

        if [ ! -f "$file_path" ]; then
            log_warn "File not found: $file_path"
            continue
        fi

        log_info "Updating: $file"

        # Use sed to replace pattern
        # Using | as delimiter to avoid issues with / in paths
        sed -i.bak "s|${pattern}|${replacement}|g" "$file_path"
        rm -f "${file_path}.bak"

        log_success "Updated $file"
    done

    # Store modified files for git add
    MODIFIED_FILES=$(echo "$files_to_update" | tr '\n' ' ')
}

# =============================================================================
# Execute based on type
# =============================================================================
case "$FILE_TYPE" in
    yaml)
        write_yaml
        ;;
    json)
        write_json
        ;;
    regex)
        write_regex
        ;;
    *)
        log_error "Unknown version file type: $FILE_TYPE"
        exit 1
        ;;
esac

# =============================================================================
# Save modified files list for update-changelog.sh
# =============================================================================
write_state "/tmp/version_files_modified.txt" "$MODIFIED_FILES"

echo ""
log_success "Version file update complete"
