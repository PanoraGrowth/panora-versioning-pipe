#!/bin/sh
# ------------------------------------------------------------------------------
# common.sh
#
# Shared utility functions used by all pipeline scripts.
# Included via "." (source) from other scripts.
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# LOGGING FUNCTIONS
# ------------------------------------------------------------------------------

log_section() {
    echo "=========================================="
    echo "  $1"
    echo "=========================================="
}

log_info() {
    echo "$1"
}

log_success() {
    echo "✓ $1"
}

log_warn() {
    echo "⚠️  $1"
}

log_error() {
    echo "ERROR: $1" >&2
}

# ------------------------------------------------------------------------------
# STATE MANAGEMENT
# ------------------------------------------------------------------------------

# Load environment variables from a file
load_env() {
    local file="$1"
    if [ -f "$file" ]; then
        . "$file"
        return 0
    else
        log_error "State file not found: $file"
        return 1
    fi
}

# Save a key-value pair to a state file
save_env() {
    local key="$1"
    local value="$2"
    local file="${3:-/tmp/scenario.env}"
    echo "${key}=${value}" >> "$file"
}

# Read value from a temp file
read_state() {
    local file="$1"
    if [ -f "$file" ]; then
        cat "$file"
    else
        return 1
    fi
}

# Write value to a temp file
write_state() {
    local file="$1"
    local value="$2"
    echo "$value" > "$file"
}

# Create a flag file
create_flag() {
    local flag="$1"
    touch "$flag"
}

# Check if a flag file exists
has_flag() {
    local flag="$1"
    [ -f "$flag" ]
}

# ------------------------------------------------------------------------------
# GIT OPERATIONS
# ------------------------------------------------------------------------------

# Fetch git refs safely
git_fetch_refs() {
    git fetch --unshallow 2>/dev/null || true
    git fetch --tags --force
}

# Push to branch with error handling
git_push_branch() {
    local branch="$1"
    if git push origin "HEAD:${branch}"; then
        log_success "Pushed to branch: $branch"
        return 0
    else
        log_error "Failed to push to branch: $branch"
        return 1
    fi
}

# Push branch and tag atomically (single push, single workflow trigger)
git_push_branch_and_tag() {
    local branch="$1"
    local tag="$2"
    if git push origin "HEAD:refs/heads/${branch}" "refs/tags/${tag}"; then
        log_success "Pushed branch ($branch) and tag ($tag) atomically"
        return 0
    else
        log_error "Failed to push branch and tag atomically"
        return 1
    fi
}

# Push a tag with error handling
git_push_tag() {
    local tag="$1"
    if git push origin "$tag"; then
        log_success "Pushed tag: $tag"
        return 0
    else
        log_error "Failed to push tag: $tag"
        return 1
    fi
}

# Get commits between two refs
git_get_commits() {
    local from="${1:-}"
    local to="${2:-HEAD}"

    if [ -z "$from" ]; then
        git log --pretty=format:"%s" "$to"
    else
        git log --pretty=format:"%s" "${from}..${to}"
    fi
}

# ------------------------------------------------------------------------------
# VALIDATIONS
# ------------------------------------------------------------------------------

# Verify that a tool is installed
require_tool() {
    local tool="$1"
    if ! command -v "$tool" >/dev/null 2>&1; then
        log_error "Required tool not found: $tool"
        exit 1
    fi
}

# Validate that an env var is defined
require_env() {
    local var="$1"
    eval "local value=\${$var:-}"
    if [ -z "$value" ]; then
        log_error "Required environment variable not set: $var"
        exit 1
    fi
}

# ------------------------------------------------------------------------------
# EXIT HELPERS
# ------------------------------------------------------------------------------

# Exit with a success message
exit_success() {
    local message="$1"
    log_section "SUCCESS"
    log_info "$message"
    exit 0
}

# Exit indicating the step was skipped (not an error)
exit_skip() {
    local message="$1"
    log_section "SKIPPED"
    log_info "$message"
    exit 0
}

# Exit with an error message
exit_error() {
    local message="$1"
    log_section "ERROR"
    log_error "$message"
    exit 1
}
