#!/bin/sh
# shellcheck shell=ash
set -e
# =============================================================================
# write-version-file.sh - Write version to configured file(s)
# =============================================================================
# Uses groups config exclusively. Each group defines files to update and
# optional trigger_paths. Type is inferred from file extension:
#   .yaml/.yml  → yq key replace (key: version)
#   .json       → yq json key replace (key: version)
#   other       → placeholder replace (requires files[].pattern)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/config-parser.sh
. "${SCRIPT_DIR}/../lib/config-parser.sh"

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# =============================================================================
# Helper: Check if a file matches a glob pattern
# =============================================================================
matches_glob() {
    local file="$1"
    local pattern="$2"

    local regex
    regex=$(echo "$pattern" | sed 's/\./\\./g' | sed 's/\*\*/DOUBLESTAR/g' | sed 's/\*/[^\/]*/g' | sed 's/DOUBLESTAR/.*/g')

    echo "$file" | grep -qE "^${regex}$"
}

# =============================================================================
# Helper: Get changed files in this PR
# =============================================================================
get_changed_files() {
    local target_branch="${VERSIONING_TARGET_BRANCH:-development}"
    git fetch origin "$target_branch" 2>/dev/null || true
    git diff --name-only "origin/${target_branch}...HEAD" 2>/dev/null | \
        grep -v "CHANGELOG.md" || true
}

# =============================================================================
# Helper: Decide if a group should be updated.
# No trigger_paths → always update. With trigger_paths → match changed files.
# =============================================================================
should_update_group() {
    local group_index="$1"
    local changed_files="$2"

    local trigger_paths
    trigger_paths=$(get_version_file_group_trigger_paths "$group_index")

    if [ -z "$trigger_paths" ]; then
        return 0
    fi

    local matched=0
    while IFS= read -r changed_file; do
        [ -z "$changed_file" ] && continue
        while IFS= read -r pattern; do
            [ -z "$pattern" ] && continue
            if matches_glob "$changed_file" "$pattern"; then
                matched=1
                break 2
            fi
        done <<EOF
$trigger_paths
EOF
    done <<EOF
$changed_files
EOF

    [ "$matched" -eq 1 ]
}

# =============================================================================
# Helper: Infer write type from file extension
# =============================================================================
infer_write_type() {
    local path="$1"
    case "$path" in
        *.yaml|*.yml) echo "yaml" ;;
        *.json)       echo "json" ;;
        *)            echo "pattern" ;;
    esac
}

# =============================================================================
# Helper: Expand a (possibly glob) path relative to REPO_ROOT
# Returns absolute paths, one per line. Uses find to stay POSIX-compatible.
# =============================================================================
expand_glob_path() {
    local pattern="$1"
    local dir base
    dir=$(dirname "${REPO_ROOT}/${pattern}")
    base=$(basename "${pattern}")
    # find with -name glob; silently returns nothing if no match
    find "$dir" -maxdepth 1 -name "$base" 2>/dev/null || true
}

# =============================================================================
# Writers
# =============================================================================
write_yaml_file() {
    local file_path="$1"
    local version="$2"

    if [ -f "$file_path" ]; then
        yq -i ".version = \"${version}\"" "$file_path"
    else
        mkdir -p "$(dirname "$file_path")"
        echo "version: \"${version}\"" > "$file_path"
    fi
    log_success "Updated $file_path"
}

write_json_file() {
    local file_path="$1"
    local version="$2"

    if [ -f "$file_path" ]; then
        yq -i -o=json ".version = \"${version}\"" "$file_path"
    else
        mkdir -p "$(dirname "$file_path")"
        echo "{\"version\": \"${version}\"}" | yq -o=json > "$file_path"
    fi
    log_success "Updated $file_path"
}

write_pattern_file() {
    local file_path="$1"
    local version="$2"
    local pattern="$3"

    if [ ! -f "$file_path" ]; then
        log_warn "File not found, skipping: $file_path"
        return 0
    fi

    sed -i.bak "s|${pattern}|${version}|g" "$file_path"
    rm -f "${file_path}.bak"
    log_success "Updated $file_path"
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
# Get version
# =============================================================================
if [ ! -f /tmp/next_version.txt ]; then
    log_error "Version file not found. Run calculate-version.sh first."
    exit 1
fi

VERSION=$(cat /tmp/next_version.txt)
log_info "Version to write: $VERSION"
echo ""

VERSION_PLAIN="$VERSION"
TAG_PREFIX=$(get_tag_prefix)
if [ -n "$TAG_PREFIX" ]; then
    VERSION_PLAIN="${VERSION#"$TAG_PREFIX"}"
fi

# =============================================================================
# Get changed files once (used for trigger_paths evaluation)
# =============================================================================
CHANGED_FILES=$(get_changed_files)

GROUPS_COUNT=$(get_version_file_groups_count)

if [ "$GROUPS_COUNT" -eq 0 ]; then
    log_warn "No groups configured in version_file. Nothing to update."
    exit 0
fi

MODIFIED_FILES=""

# =============================================================================
# Main loop: iterate groups → files → write
# =============================================================================
i=0
while [ "$i" -lt "$GROUPS_COUNT" ]; do
    GROUP_NAME=$(get_version_file_group_name "$i")

    if ! should_update_group "$i" "$CHANGED_FILES"; then
        log_info "Group '$GROUP_NAME': trigger_paths did not match changed files, skipping"
        i=$((i + 1))
        continue
    fi

    log_info "Group '$GROUP_NAME': updating files"

    FILES_COUNT=$(get_version_file_group_files_count "$i")
    j=0
    while [ "$j" -lt "$FILES_COUNT" ]; do
        FILE_PATH_PATTERN=$(get_version_file_group_file_path "$i" "$j")
        FILE_PATTERN=$(get_version_file_group_file_pattern "$i" "$j")

        if [ -z "$FILE_PATH_PATTERN" ]; then
            log_warn "Group '$GROUP_NAME' file[$j]: path is empty, skipping"
            j=$((j + 1))
            continue
        fi

        WRITE_TYPE=$(infer_write_type "$FILE_PATH_PATTERN")

        if [ "$WRITE_TYPE" = "pattern" ] && [ -z "$FILE_PATTERN" ]; then
            log_error "Group '$GROUP_NAME' file[$j]: '$FILE_PATH_PATTERN' requires a pattern (non-yaml/json extension) but none is configured"
            exit 1
        fi

        EXPANDED=$(expand_glob_path "$FILE_PATH_PATTERN")

        if [ -z "$EXPANDED" ]; then
            log_warn "Group '$GROUP_NAME' file[$j]: no files matched '$FILE_PATH_PATTERN', skipping"
            j=$((j + 1))
            continue
        fi

        while IFS= read -r actual_file; do
            [ -z "$actual_file" ] && continue
            case "$WRITE_TYPE" in
                yaml)    write_yaml_file "$actual_file" "$VERSION_PLAIN" ;;
                json)    write_json_file "$actual_file" "$VERSION_PLAIN" ;;
                pattern) write_pattern_file "$actual_file" "$VERSION" "$FILE_PATTERN" ;;
            esac
            MODIFIED_FILES="${MODIFIED_FILES} ${actual_file}"
        done <<EOF
$EXPANDED
EOF

        j=$((j + 1))
    done

    i=$((i + 1))
done

# =============================================================================
# Save modified files list for downstream scripts
# =============================================================================
write_state "/tmp/version_files_modified.txt" "$MODIFIED_FILES"

echo ""
log_success "Version file update complete"
