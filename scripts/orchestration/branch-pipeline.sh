#!/bin/sh
# ============================================================================
# Script: branch-pipeline.sh
# Description: Main orchestrator for branch pipeline (create tags)
# Inputs: VERSIONING_BRANCH, VERSIONING_COMMIT
# Outputs: Version tag created and pushed
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AUTOMATIONS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load common functions and config
. "${AUTOMATIONS_DIR}/lib/common.sh"
. "${AUTOMATIONS_DIR}/lib/config-parser.sh"

log_section "BRANCH PIPELINE - TAG CREATION"
log_info "Branch: $VERSIONING_BRANCH"
echo ""

# Get tag branch from config
TAG_BRANCH=$(get_tag_branch)

# Only create tags for configured branch
if [ "$VERSIONING_BRANCH" != "$TAG_BRANCH" ]; then
    log_info "Tag creation only runs on $TAG_BRANCH branch"
    log_info "Current branch: $VERSIONING_BRANCH"
    log_info "Skipping tag creation"
    exit 0
fi

# ============================================================================
# Detect scenario (development_release vs hotfix) for the commit being released.
# Writes /tmp/scenario.env which calculate-version.sh and the CHANGELOG scripts
# downstream consume. MUST run before calculate-version.sh so hotfix routing
# drives the PATCH bump (when patch.enabled is true) or the no-op path (when
# patch.enabled is false).
# ============================================================================
"${AUTOMATIONS_DIR}/detection/detect-scenario.sh"

# ============================================================================
# Calculate version (writes /tmp/next_version.txt, /tmp/bump_type.txt, /tmp/latest_tag.txt)
# ============================================================================
"${AUTOMATIONS_DIR}/versioning/calculate-version.sh"

# Read results from state files
BUMP_TYPE=$(read_state "/tmp/bump_type.txt" || echo "")
if [ -z "$BUMP_TYPE" ]; then
    log_info "No new commits since last tag - skipping tag creation"
    exit 0
fi

NEW_TAG=$(read_state "/tmp/next_version.txt")
LATEST_TAG=$(read_state "/tmp/latest_tag.txt" || echo "")

# Extract version from tag for display
CURRENT_VERSION=$(parse_tag_to_version "$NEW_TAG" 2>/dev/null || echo "$NEW_TAG")

log_info "New tag: $NEW_TAG"
log_info "Bump type: $BUMP_TYPE"
echo ""

# ============================================================================
# Generate CHANGELOG + version files (before tag creation)
# ============================================================================

# /tmp/scenario.env was populated by detect-scenario.sh above; reuse it as-is
export CHANGELOG_BASE_REF="${LATEST_TAG}"

echo ""

# Write version to file(s) if configured
"${AUTOMATIONS_DIR}/versioning/write-version-file.sh"

echo ""

# Generate per-folder CHANGELOGs (if enabled — runs first for exclusive routing)
"${AUTOMATIONS_DIR}/changelog/generate-changelog-per-folder.sh"

echo ""

# Generate root CHANGELOG (excludes commits already routed to per-folder)
"${AUTOMATIONS_DIR}/changelog/generate-changelog-last-commit.sh"

echo ""

# Commit and push CHANGELOG + version files
"${AUTOMATIONS_DIR}/changelog/update-changelog.sh"

echo ""

# ============================================================================
# Create and push tag (on the CHANGELOG commit, not the merge commit)
# ============================================================================
log_section "CREATING VERSION TAG"
log_info "Tag: $NEW_TAG"
echo ""

git tag -a "$NEW_TAG" \
    -m "Release version $CURRENT_VERSION ($BUMP_TYPE)" \
    -m "" \
    -m "Automated by CI pipeline" \
    -m "Branch: $VERSIONING_BRANCH" \
    -m "Commit: $(git rev-parse HEAD)" \
    -m "Timestamp: $(date +"%Y-%m-%d %H:%M:%S %Z")"

log_success "Tag created successfully"
echo ""

log_info "Pushing CHANGELOG commit and tag atomically..."
git_push_branch_and_tag "$VERSIONING_BRANCH" "$NEW_TAG"

# Clean up flag file
rm -f /tmp/changelog_committed.flag

echo ""
log_section "VERSION TAG CREATED SUCCESSFULLY"
log_info "Previous Tag:      ${LATEST_TAG:-none}"
log_info "New Version:       $CURRENT_VERSION"
log_info "Bump Type:         $BUMP_TYPE"
log_info "New Tag:           $NEW_TAG"
log_info "Branch:            $VERSIONING_BRANCH"
