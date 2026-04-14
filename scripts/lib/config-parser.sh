#!/bin/sh
# shellcheck shell=ash
# =============================================================================
# config-parser.sh - Parser for versioning configuration
# Reads defaults.yml and merges with .versioning.yml overrides
# =============================================================================

# Find repository root
find_repo_root() {
    git rev-parse --show-toplevel 2>/dev/null || pwd
}

# Paths
REPO_ROOT=$(find_repo_root)
CONFIG_FILE="${REPO_ROOT}/.versioning.yml"
MERGED_CONFIG="/tmp/.versioning-merged.yml"

# Find defaults.yml: relative to this script first, then Docker path
_PARSER_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo "/pipe/lib")"
if [ -f "${_PARSER_DIR}/../defaults.yml" ]; then
    DEFAULTS_FILE="$(cd "${_PARSER_DIR}/.." && pwd)/defaults.yml"
elif [ -f "/pipe/defaults.yml" ]; then
    DEFAULTS_FILE="/pipe/defaults.yml"
else
    DEFAULTS_FILE="${REPO_ROOT}/automations/defaults.yml"
fi

# =============================================================================
# CONFIGURATION LOADING
# =============================================================================

# Merge defaults with project config (call once at script start)
load_config() {
    if [ ! -f "$DEFAULTS_FILE" ]; then
        echo "ERROR: defaults.yml not found at $DEFAULTS_FILE" >&2
        return 1
    fi

    if [ -f "$CONFIG_FILE" ]; then
        # Merge: defaults + project overrides
        yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' \
            "$DEFAULTS_FILE" "$CONFIG_FILE" > "$MERGED_CONFIG" 2>/dev/null
    else
        # Use defaults only
        cp "$DEFAULTS_FILE" "$MERGED_CONFIG"
    fi

    # Apply commit_type_overrides: patch or add commit types by name
    apply_commit_type_overrides
}

# Patch commit_types array using commit_type_overrides map
# - If a type name exists in commit_types → update its fields
# - If a type name doesn't exist → append as new entry
# This avoids the yq array-replace problem: users only specify what they want to change
apply_commit_type_overrides() {
    local has_overrides
    has_overrides=$(yq -r '.commit_type_overrides // null' "$MERGED_CONFIG" 2>/dev/null)
    if [ -z "$has_overrides" ] || [ "$has_overrides" = "null" ]; then
        return
    fi

    # Process each override using while read (handles multiline output correctly)
    yq -r '.commit_type_overrides | keys | .[]' "$MERGED_CONFIG" 2>/dev/null | while IFS= read -r type_name; do
        [ -z "$type_name" ] && continue

        # Check if type already exists in commit_types array
        local exists
        exists=$(yq -r ".commit_types[] | select(.name == \"$type_name\") | .name" "$MERGED_CONFIG" 2>/dev/null)

        if [ -n "$exists" ]; then
            # Patch existing type: update each override field
            yq -r ".commit_type_overrides.$type_name | keys | .[]" "$MERGED_CONFIG" 2>/dev/null | while IFS= read -r field; do
                [ -z "$field" ] && continue
                local value
                value=$(yq -r ".commit_type_overrides.$type_name.$field" "$MERGED_CONFIG" 2>/dev/null)
                yq -i "(.commit_types[] | select(.name == \"$type_name\")).$field = \"$value\"" "$MERGED_CONFIG" 2>/dev/null
            done
        else
            # New type: append with name + all override fields merged by yq
            yq -i ".commit_types += [{\"name\": \"$type_name\"} * .commit_type_overrides.$type_name]" "$MERGED_CONFIG" 2>/dev/null
        fi
    done
}

# Initialize config on source
load_config

# Generic config reader
config_get() {
    local path="$1"
    local default="$2"

    local value
    value=$(yq -r ".$path" "$MERGED_CONFIG" 2>/dev/null)
    # Treat absent keys (null) as missing; treat all other values including "false" and "0" as set
    if [ -n "$value" ] && [ "$value" != "null" ]; then
        echo "$value"
    elif [ -n "$default" ]; then
        echo "$default"
    fi
}

# Read array as space-separated values
config_get_array() {
    local path="$1"
    local result
    result=$(yq -r ".$path // []" "$MERGED_CONFIG" 2>/dev/null | yq -r '.[]' 2>/dev/null | tr '\n' ' ' | sed 's/ $//')
    echo "$result"
}

# =============================================================================
# COMMITS FORMAT CONFIGURATION
# =============================================================================

# Get commits format: "ticket" or "conventional"
get_commits_format() {
    config_get "commits.format" "ticket"
}

# Check if using conventional commits format
is_conventional_commits() {
    [ "$(get_commits_format)" = "conventional" ]
}

# =============================================================================
# TICKET CONFIGURATION
# =============================================================================

# Get ticket prefixes as pipe-separated pattern (empty if none defined)
get_ticket_prefixes_pattern() {
    local prefixes
    prefixes=$(config_get_array "tickets.prefixes")
    if [ -n "$prefixes" ]; then
        echo "$prefixes" | tr ' ' '|'
    fi
    # Returns empty if no prefixes defined
}

# Check if ticket prefixes are configured
has_ticket_prefixes() {
    local prefixes
    prefixes=$(get_ticket_prefixes_pattern)
    [ -n "$prefixes" ]
}

# Check if ticket prefix is required
is_ticket_required() {
    local required
    required=$(config_get "tickets.required" "false")
    [ "$required" = "true" ]
}

# Get ticket URL base
get_ticket_url() {
    config_get "tickets.url" ""
}

# =============================================================================
# VERSION CONFIGURATION
# =============================================================================

is_component_enabled() {
    local component="$1"
    local enabled
    enabled=$(config_get "version.components.${component}.enabled" "false")
    [ "$enabled" = "true" ]
}

get_component_initial() {
    local component="$1"
    local default="$2"
    config_get "version.components.${component}.initial" "$default"
}

get_timestamp_format() {
    config_get "version.components.timestamp.format" "%Y%m%d%H%M%S"
}

get_timezone() {
    config_get "version.components.timestamp.timezone" "UTC"
}

get_version_separator() {
    config_get "version.separators.version" "."
}

get_timestamp_separator() {
    config_get "version.separators.timestamp" "."
}

get_tag_suffix() {
    config_get "version.separators.suffix" ""
}

use_tag_prefix_v() {
    local enabled
    enabled=$(config_get "version.tag_prefix_v" "false")
    [ "$enabled" = "true" ]
}

get_tag_prefix() {
    if use_tag_prefix_v; then
        echo "v"
    fi
}

# =============================================================================
# COMMIT TYPES CONFIGURATION
# =============================================================================

# Get all commit type names as pipe-separated pattern
get_commit_types_pattern() {
    local types
    types=$(yq -r '.commit_types[].name' "$MERGED_CONFIG" 2>/dev/null | tr '\n' '|' | sed 's/|$//')
    if [ -n "$types" ]; then
        echo "$types"
    fi
}

# Get bump action for a commit type
get_bump_action() {
    local type="$1"
    local bump
    bump=$(yq -r ".commit_types[] | select(.name == \"$type\") | .bump // \"none\"" "$MERGED_CONFIG" 2>/dev/null)
    if [ -n "$bump" ] && [ "$bump" != "null" ]; then
        echo "$bump"
    else
        echo "none"
    fi
}

# Get types that trigger a specific bump action
get_types_for_bump() {
    local bump="$1"
    yq -r ".commit_types[] | select(.bump == \"$bump\") | .name" "$MERGED_CONFIG" 2>/dev/null | tr '\n' '|' | sed 's/|$//'
}

# Get emoji for a commit type
get_commit_type_emoji() {
    local type="$1"
    yq -r ".commit_types[] | select(.name == \"$type\") | .emoji // \"\"" "$MERGED_CONFIG" 2>/dev/null
}

# =============================================================================
# CHANGELOG CONFIGURATION
# =============================================================================

get_changelog_file() {
    config_get "changelog.file" "CHANGELOG.md"
}

get_changelog_title() {
    config_get "changelog.title" "Changelog"
}

get_changelog_format() {
    config_get "changelog.format" "minimal"
}

use_changelog_emojis() {
    local use
    use=$(config_get "changelog.use_emojis" "false")
    [ "$use" = "true" ]
}

include_commit_link() {
    local include
    include=$(config_get "changelog.include_commit_link" "true")
    [ "$include" = "true" ]
}

include_ticket_link() {
    local include
    include=$(config_get "changelog.include_ticket_link" "true")
    [ "$include" = "true" ]
}

include_author() {
    local include
    include=$(config_get "changelog.include_author" "true")
    [ "$include" = "true" ]
}

get_commit_url() {
    config_get "changelog.commit_url" ""
}

get_ticket_link_label() {
    config_get "changelog.ticket_link_label" "View ticket"
}

# =============================================================================
# CHANGELOG CONFIGURATION (extended)
# =============================================================================

# Get changelog mode: "last_commit" or "full"
get_changelog_mode() {
    config_get "changelog.mode" "last_commit"
}

# Check if full history mode is enabled
is_full_changelog_mode() {
    [ "$(get_changelog_mode)" = "full" ]
}

# =============================================================================
# CHANGELOG PER-FOLDER CONFIGURATION
# =============================================================================

# Check if per-folder changelogs are enabled
is_per_folder_changelog_enabled() {
    local enabled
    enabled=$(config_get "changelog.per_folder.enabled" "false")
    [ "$enabled" = "true" ]
}

# Get configured folders for per-folder changelogs (space-separated)
# Supports both "folders" (new) and "root_folders" (legacy) config keys
get_per_folder_folders() {
    local folders
    folders=$(config_get_array "changelog.per_folder.folders")
    if [ -n "$folders" ]; then
        echo "$folders"
    else
        # Legacy fallback
        config_get_array "changelog.per_folder.root_folders"
    fi
}

# Get folder pattern regex (e.g. "^[0-9]{3}-" for numbered folders)
get_per_folder_pattern() {
    config_get "changelog.per_folder.folder_pattern" ""
}

# Get scope matching mode: "suffix" or "exact"
get_per_folder_scope_matching() {
    config_get "changelog.per_folder.scope_matching" "suffix"
}

# Get fallback mode: "root" or "file_path"
get_per_folder_fallback() {
    config_get "changelog.per_folder.fallback" "root"
}

# Extract scope from a conventional commit message
# Input: "feat(cluster-ecs): add new config" -> Output: "cluster-ecs"
# Input: "feat: add feature" -> Output: "" (no scope)
extract_scope_from_commit() {
    local commit_msg="$1"
    echo "$commit_msg" | sed -n 's/^[a-z]*(\([^)]*\)):.*/\1/p'
}

# Find folder matching a scope
# Routing: scope → folder match → subfolder discovery → (caller handles fallback)
# Args: scope, folders (space-separated), folder_pattern, scope_matching
find_folder_for_scope() {
    local scope="$1"
    local folders="$2"
    local folder_pattern="$3"
    local scope_matching="$4"

    if [ -z "$scope" ]; then
        return
    fi

    for folder in $folders; do
        local folder_path="${REPO_ROOT}/${folder}"
        if [ ! -d "$folder_path" ]; then
            continue
        fi

        local folder_name
        folder_name=$(basename "$folder")

        if [ "$scope_matching" = "exact" ]; then
            # Step 2: Exact match — scope IS the configured folder name
            if [ "$scope" = "$folder_name" ]; then
                echo "$folder_path"
                return
            fi

            # Step 3: Subfolder discovery — scope matches a subfolder within this folder
            # Scans one level deep only
            if [ -d "${folder_path}/${scope}" ]; then
                echo "${folder_path}/${scope}"
                return
            fi
        elif [ "$scope_matching" = "suffix" ]; then
            # Suffix match: search subfolders whose name ends with the scope
            for subfolder in "$folder_path"/*/; do
                [ -d "$subfolder" ] || continue
                local subfolder_name
                subfolder_name=$(basename "$subfolder")

                # Apply folder_pattern filter if set
                if [ -n "$folder_pattern" ]; then
                    echo "$subfolder_name" | grep -qE "$folder_pattern" || continue
                fi

                # Check if folder name ends with the scope
                case "$subfolder_name" in
                    *-"$scope") echo "$subfolder"; return ;;
                esac
            done
        fi
    done
}

# Find folder for a commit by checking which configured folder contains the modified files
# Args: commit_hash, folders (space-separated)
# Returns: folder path if files fall within exactly ONE configured folder, empty otherwise
find_folder_by_file_path() {
    local commit_hash="$1"
    local folders="$2"

    # Get files modified by this commit
    local changed_files
    changed_files=$(git diff-tree --no-commit-id --name-only -r "$commit_hash" 2>/dev/null)
    if [ -z "$changed_files" ]; then
        return
    fi

    local _matched=""
    for file in $changed_files; do
        [ -z "$file" ] && continue
        for folder in $folders; do
            case "$file" in
                "${folder}"/*)
                    if [ -z "$_matched" ]; then
                        _matched="$folder"
                    elif [ "$_matched" != "$folder" ]; then
                        # Ambiguous — files in multiple folders
                        return
                    fi
                    break
                    ;;
            esac
        done
    done

    if [ -n "$_matched" ]; then
        echo "${REPO_ROOT}/${_matched}"
    fi
}

# =============================================================================
# VALIDATION CONFIGURATION
# =============================================================================

require_ticket_prefix() {
    # Only require if: tickets.required=true AND prefixes are defined
    if ! is_ticket_required; then
        return 1
    fi
    has_ticket_prefixes
}

require_commit_types() {
    local required
    required=$(config_get "validation.require_commit_types" "true")
    [ "$required" = "true" ]
}

# True when type validation is active AND changelog.mode is full (all commits must be typed)
require_commit_types_for_all() {
    require_commit_types && is_full_changelog_mode
}

# Get ignore patterns as pipe-separated regex for grep -E
get_ignore_patterns_regex() {
    local patterns
    patterns=$(config_get_array "validation.ignore_patterns")
    if [ -n "$patterns" ]; then
        echo "$patterns" | tr ' ' '|'
    fi
}

# =============================================================================
# HOTFIX CONFIGURATION
# =============================================================================

# Return hotfix keyword glob patterns (newline-separated).
# Handles both formats:
#   - Array (new):  keyword: ["hotfix:*", "hotfix(*"]  → return items as-is
#   - Scalar (legacy): keyword: "hotfix"  → auto-expand to "hotfix:*\nhotfix(*"
get_hotfix_keywords() {
    local ktype
    ktype=$(yq -r '.hotfix.keyword | type' "$MERGED_CONFIG" 2>/dev/null)
    if [ "$ktype" = "!!seq" ]; then
        yq -r '.hotfix.keyword[]' "$MERGED_CONFIG" 2>/dev/null
    else
        local kw
        kw=$(config_get "hotfix.keyword" "hotfix")
        printf '%s\n%s\n' "${kw}:*" "${kw}(*"
    fi
}

# Return the base hotfix keyword (for branch prefix matching in PR context).
# Extracts the base word from the first keyword pattern by stripping glob chars.
get_hotfix_keyword() {
    local first
    first=$(get_hotfix_keywords | head -1)
    echo "$first" | sed 's/[:([].*$//'
}

# =============================================================================
# BRANCHES CONFIGURATION
# =============================================================================

get_development_branch() {
    config_get "branches.development" "development"
}

get_preprod_branch() {
    config_get "branches.pre_production" "pre-production"
}

get_production_branch() {
    config_get "branches.production" "main"
}

get_tag_branch() {
    config_get "branches.tag_on" "development"
}

# =============================================================================
# PATTERN BUILDERS
# =============================================================================

# Count enabled base version components (period, major, minor).
# NOTE: patch is intentionally excluded — it is an OPTIONAL trailing component
# rendered only when patch > 0, so it must not inflate the base component count
# used to build the fixed-width tag regex.
get_enabled_component_count() {
    local count=0
    is_component_enabled "period" && count=$((count + 1))
    is_component_enabled "major" && count=$((count + 1))
    is_component_enabled "minor" && count=$((count + 1))
    echo "$count"
}

# Get tag version pattern for filtering git tags
# Dynamically built based on enabled components, timestamp, and prefix
get_tag_pattern() {
    local prefix=""
    use_tag_prefix_v && prefix="v"

    local parts
    parts=$(get_enabled_component_count)
    # Build base pattern: [0-9]+ repeated for each enabled component
    local base="[0-9]+"
    local i=1
    while [ "$i" -lt "$parts" ]; do
        base="${base}\.[0-9]+"
        i=$((i + 1))
    done

    # Optional trailing patch group — matches both backward-compat tags
    # (v0.5.9, patch omitted) and hotfix tags (v0.5.9.1, patch present)
    local patch_group=""
    if is_component_enabled "patch"; then
        patch_group="(\.[0-9]+)?"
    fi

    if is_component_enabled "timestamp"; then
        echo "^${prefix}${base}${patch_group}\.[0-9]{12,14}(-[0-9]+)?\$"
    else
        echo "^${prefix}${base}${patch_group}\$"
    fi
}

# Build version string from period/major/minor/patch based on enabled components.
# Patch is rendered only when enabled AND non-zero, so tags like v0.5.9 (patch=0)
# stay identical to the pre-patch-component behaviour.
build_version_string() {
    local period="$1" major="$2" minor="$3" patch="${4:-0}"
    local sep
    sep=$(get_version_separator)
    local version=""

    if is_component_enabled "period"; then
        version="${period}"
    fi
    if is_component_enabled "major"; then
        [ -n "$version" ] && version="${version}${sep}"
        version="${version}${major}"
    fi
    if is_component_enabled "minor"; then
        [ -n "$version" ] && version="${version}${sep}"
        version="${version}${minor}"
    fi
    if is_component_enabled "patch"; then
        # Numeric gate: append only when patch is a positive integer
        if [ -n "$patch" ] && [ "$patch" -gt 0 ] 2>/dev/null; then
            [ -n "$version" ] && version="${version}${sep}"
            version="${version}${patch}"
        fi
    fi

    echo "$version"
}

# Strip prefix and timestamp from a tag to get the version string
parse_tag_to_version() {
    local tag="$1"
    # Strip v prefix if present
    local stripped="${tag#v}"

    if is_component_enabled "timestamp"; then
        echo "$stripped" | sed -E 's/\.[0-9]{12,14}(-[0-9]+)?$//'
    else
        local suffix
        suffix=$(get_tag_suffix)
        if [ -n "$suffix" ]; then
            echo "$stripped" | sed "s/${suffix}\$//"
        else
            echo "$stripped"
        fi
    fi
}

# Parse version string into PARSED_PERIOD, PARSED_MAJOR, PARSED_MINOR, PARSED_PATCH
# Sets global variables — call after parse_tag_to_version
# shellcheck disable=SC2034
parse_version_components() {
    local version="$1"
    local pos=1

    if is_component_enabled "period"; then
        PARSED_PERIOD=$(echo "$version" | cut -d. -f"${pos}")
        pos=$((pos + 1))
    else
        PARSED_PERIOD="0"
    fi

    if is_component_enabled "major"; then
        PARSED_MAJOR=$(echo "$version" | cut -d. -f"${pos}")
        pos=$((pos + 1))
    else
        PARSED_MAJOR="0"
    fi

    if is_component_enabled "minor"; then
        PARSED_MINOR=$(echo "$version" | cut -d. -f"${pos}")
        pos=$((pos + 1))
    else
        PARSED_MINOR="0"
    fi

    # Patch: optional trailing field — absent for v0.5.9, present for v0.5.9.1
    if is_component_enabled "patch"; then
        local total_fields
        total_fields=$(echo "$version" | awk -F. '{print NF}')
        if [ "$total_fields" -ge "$pos" ]; then
            PARSED_PATCH=$(echo "$version" | cut -d. -f"${pos}")
        else
            PARSED_PATCH="0"
        fi
    else
        PARSED_PATCH="0"
    fi
}

# Build full tag: prefix + version + timestamp (if enabled) + suffix
build_full_tag() {
    local version="$1"
    local prefix
    prefix=$(get_tag_prefix)
    local suffix
    suffix=$(get_tag_suffix)

    if is_component_enabled "timestamp"; then
        local ts_sep
        ts_sep=$(get_timestamp_separator)
        local tz
        tz=$(get_timezone)
        local fmt
        fmt=$(get_timestamp_format)
        export TZ="$tz"
        local timestamp
        timestamp=$(date +"$fmt")
        echo "${prefix}${version}${ts_sep}${timestamp}${suffix}"
    else
        echo "${prefix}${version}${suffix}"
    fi
}

# Build prefix pattern for validation
# Ticket: "^(AM|TECH)-[0-9]+ - " or empty if no prefixes
# Conventional: empty (no prefix needed)
build_ticket_prefix_pattern() {
    if is_conventional_commits; then
        # Conventional commits don't use ticket prefixes
        return
    fi

    local prefixes
    prefixes=$(get_ticket_prefixes_pattern)
    if [ -n "$prefixes" ]; then
        echo "^(${prefixes})-[0-9]+ - "
    fi
}

# Build full commit pattern (with type)
# Ticket: "^(AM|TECH)-[0-9]+ - (feat|fix|...): "
# Conventional: "^(feat|fix|...)(\\(.+\\))?: "
build_ticket_full_pattern() {
    local types
    types=$(get_commit_types_pattern)

    if is_conventional_commits; then
        # Conventional commits: type(scope): message (scope optional)
        echo "^(${types})(\\(.+\\))?:"
        return
    fi

    local prefixes
    prefixes=$(get_ticket_prefixes_pattern)
    if [ -n "$prefixes" ]; then
        echo "^(${prefixes})-[0-9]+ - (${types}):"
    else
        # No prefix required, just check for type
        echo "^.* - (${types}):|^(${types}):"
    fi
}

# Build pattern to detect bump types
build_bump_pattern() {
    local bump_type="$1"
    local types
    types=$(get_types_for_bump "$bump_type")

    if [ -z "$types" ]; then
        return
    fi

    if is_conventional_commits; then
        echo "^(${types})(\\(.+\\))?:"
        return
    fi

    local prefixes
    prefixes=$(get_ticket_prefixes_pattern)
    if [ -n "$prefixes" ]; then
        echo "^(${prefixes})-[0-9]+ - (${types}):"
    else
        echo "^.* - (${types}):|^(${types}):"
    fi
}

# Get example prefix for messages (first prefix or generic)
get_example_prefix() {
    if is_conventional_commits; then
        echo "feat(scope)"
        return
    fi

    local prefixes
    prefixes=$(config_get_array "tickets.prefixes")
    local first
    first=$(echo "$prefixes" | awk '{print $1}')
    if [ -n "$first" ]; then
        echo "$first"
    else
        echo "TICKET"
    fi
}

# =============================================================================
# VERSION FILE CONFIGURATION
# =============================================================================

# Check if version file feature is enabled
is_version_file_enabled() {
    local enabled
    enabled=$(config_get "version_file.enabled" "false")
    [ "$enabled" = "true" ]
}

# Get version file type (yaml | json | regex)
get_version_file_type() {
    config_get "version_file.type" "yaml"
}

# Get version file path (for yaml/json types)
get_version_file_path() {
    config_get "version_file.file" "version.yaml"
}

# Get version file key (for yaml/json types)
get_version_file_key() {
    config_get "version_file.key" "version"
}

# Get version files list (for regex type) - returns newline-separated
get_version_files_list() {
    yq -r '.version_file.files // [] | .[]' "$MERGED_CONFIG" 2>/dev/null
}

# Get version file pattern (for regex type)
get_version_file_pattern() {
    config_get "version_file.pattern" ""
}

# Get version file replacement (for regex type)
get_version_file_replacement() {
    config_get "version_file.replacement" ""
}

# =============================================================================
# VERSION FILE GROUPS (Monorepo Support)
# =============================================================================

# Check if groups are configured
has_version_file_groups() {
    local count
    count=$(yq -r '.version_file.groups // [] | length' "$MERGED_CONFIG" 2>/dev/null)
    [ "$count" -gt 0 ]
}

# Get number of groups
get_version_file_groups_count() {
    yq -r '.version_file.groups // [] | length' "$MERGED_CONFIG" 2>/dev/null
}

# Get group name by index
get_version_file_group_name() {
    local index="$1"
    yq -r ".version_file.groups[$index].name // \"group_$index\"" "$MERGED_CONFIG" 2>/dev/null
}

# Get group trigger_paths by index (newline-separated)
get_version_file_group_trigger_paths() {
    local index="$1"
    yq -r ".version_file.groups[$index].trigger_paths // [] | .[]" "$MERGED_CONFIG" 2>/dev/null
}

# Get group files by index (newline-separated)
get_version_file_group_files() {
    local index="$1"
    yq -r ".version_file.groups[$index].files // [] | .[]" "$MERGED_CONFIG" 2>/dev/null
}

# Check if group has update_all flag
is_version_file_group_update_all() {
    local index="$1"
    local update_all
    update_all=$(yq -r ".version_file.groups[$index].update_all // false" "$MERGED_CONFIG" 2>/dev/null)
    [ "$update_all" = "true" ]
}

# Get unmatched files behavior
get_unmatched_files_behavior() {
    config_get "version_file.unmatched_files_behavior" "update_all"
}
