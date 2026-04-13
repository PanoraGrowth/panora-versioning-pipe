#!/bin/sh
# shellcheck shell=ash
# =============================================================================
# notify-teams.sh - Send notification to Microsoft Teams
# =============================================================================
# Usage: ./notify-teams.sh <trigger_type>
#   trigger_type: "success" or "failure"
# Requires: TEAMS_WEBHOOK_URL environment variable
# Configuration: Read from defaults.yml + .versioning.yml
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

TRIGGER_TYPE="$1"

# Validate trigger type
if [ -z "$TRIGGER_TYPE" ]; then
    echo "Usage: $0 <trigger_type>"
    echo "  trigger_type: 'success' or 'failure'"
    exit 1
fi

if [ "$TRIGGER_TYPE" != "success" ] && [ "$TRIGGER_TYPE" != "failure" ]; then
    echo "Error: Invalid trigger type '$TRIGGER_TYPE'. Must be 'success' or 'failure'"
    exit 1
fi

# Load and merge configuration
# Find defaults.yml: relative to this script first, then Docker path
if [ -f "${SCRIPT_DIR}/../defaults.yml" ]; then
    DEFAULTS_FILE="$(cd "${SCRIPT_DIR}/.." && pwd)/defaults.yml"
elif [ -f "/pipe/defaults.yml" ]; then
    DEFAULTS_FILE="/pipe/defaults.yml"
else
    DEFAULTS_FILE="$REPO_ROOT/automations/defaults.yml"
fi
PROJECT_FILE="$REPO_ROOT/.versioning.yml"

if [ ! -f "$DEFAULTS_FILE" ]; then
    echo "Error: defaults.yml not found at $DEFAULTS_FILE"
    exit 1
fi

# Merge configs (project overrides defaults)
if [ -f "$PROJECT_FILE" ]; then
    MERGED_CONFIG=$(mktemp)
    yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' "$DEFAULTS_FILE" "$PROJECT_FILE" > "$MERGED_CONFIG"
else
    MERGED_CONFIG="$DEFAULTS_FILE"
fi

# Read notification settings (handle boolean false correctly - yq's // operator treats false as falsy)
TEAMS_ENABLED_RAW=$(yq -r '.notifications.teams.enabled' "$MERGED_CONFIG")
ON_SUCCESS_RAW=$(yq -r '.notifications.teams.on_success' "$MERGED_CONFIG")
ON_FAILURE_RAW=$(yq -r '.notifications.teams.on_failure' "$MERGED_CONFIG")
PAYLOAD_TEMPLATE_PATH_RAW=$(yq -r '.notifications.teams.payload_template' "$MERGED_CONFIG")

# Apply defaults only if value is null (missing), not if it's false
[ "$TEAMS_ENABLED_RAW" = "null" ] && TEAMS_ENABLED="true" || TEAMS_ENABLED="$TEAMS_ENABLED_RAW"
[ "$ON_SUCCESS_RAW" = "null" ] && ON_SUCCESS="true" || ON_SUCCESS="$ON_SUCCESS_RAW"
[ "$ON_FAILURE_RAW" = "null" ] && ON_FAILURE="true" || ON_FAILURE="$ON_FAILURE_RAW"

# Set default payload template path based on environment
if [ "$PAYLOAD_TEMPLATE_PATH_RAW" = "null" ]; then
    if [ -f "${SCRIPT_DIR}/templates/webhook_pipeline_payload.json" ]; then
        # Running relative to script location
        PAYLOAD_TEMPLATE_PATH="${SCRIPT_DIR}/templates/webhook_pipeline_payload.json"
    elif [ -f "/pipe/reporting/templates/webhook_pipeline_payload.json" ]; then
        # Running as Docker pipe
        PAYLOAD_TEMPLATE_PATH="/pipe/reporting/templates/webhook_pipeline_payload.json"
    else
        PAYLOAD_TEMPLATE_PATH="$REPO_ROOT/automations/reporting/templates/webhook_pipeline_payload.json"
    fi
else
    PAYLOAD_TEMPLATE_PATH="$PAYLOAD_TEMPLATE_PATH_RAW"
fi

# Clean up temp file if created
if [ -f "$PROJECT_FILE" ]; then
    rm -f "$MERGED_CONFIG"
fi

# Check if notifications are enabled
if [ "$TEAMS_ENABLED" != "true" ]; then
    echo "Teams notifications are disabled in configuration"
    exit 0
fi

# Check if this trigger type is enabled and set notification variables
if [ "$TRIGGER_TYPE" = "success" ]; then
    if [ "$ON_SUCCESS" != "true" ]; then
        echo "Teams notification on success is disabled"
        exit 0
    fi
    export NOTIFICATION_STYLE="accent"
    export NOTIFICATION_ICON="https://cdn-icons-png.flaticon.com/512/845/845646.png"
    export NOTIFICATION_TITLE="✅ Pipeline Successful"
    export NOTIFICATION_SUBTITLE="PR validation completed"
else
    if [ "$ON_FAILURE" != "true" ]; then
        echo "Teams notification on failure is disabled"
        exit 0
    fi
    export NOTIFICATION_STYLE="attention"
    export NOTIFICATION_ICON="https://cdn-icons-png.flaticon.com/512/1828/1828665.png"
    export NOTIFICATION_TITLE="❌ Pipeline Failed"
    export NOTIFICATION_SUBTITLE="Commit validation failed"
fi

# Use path directly (already absolute for Docker, or includes REPO_ROOT for local)
PAYLOAD_TEMPLATE="$PAYLOAD_TEMPLATE_PATH"

# Validate payload template exists
if [ ! -f "$PAYLOAD_TEMPLATE" ]; then
    echo "Error: Payload template not found: $PAYLOAD_TEMPLATE"
    exit 1
fi

# Check webhook URL
if [ -z "$TEAMS_WEBHOOK_URL" ]; then
    echo "Warning: TEAMS_WEBHOOK_URL not configured, skipping notification"
    exit 0
fi

echo "Sending Teams notification ($TRIGGER_TYPE)..."

# Export additional variables for envsubst
# Core pipeline context — sourced from generic VERSIONING_* vars
export BITBUCKET_COMMIT_SHORT
BITBUCKET_COMMIT_SHORT=$(echo "${VERSIONING_COMMIT:-unknown}" | cut -c1-7)
export BITBUCKET_PR_AUTHOR
BITBUCKET_PR_AUTHOR=$(git log -1 --format='%an' 2>/dev/null || echo "N/A")
export BITBUCKET_PR_ID="${VERSIONING_PR_ID:-N/A}"
export BITBUCKET_BRANCH="${VERSIONING_BRANCH:-}"

# Platform-specific reporting vars (BITBUCKET_REPO_SLUG, BITBUCKET_WORKSPACE,
# BITBUCKET_BUILD_NUMBER) must be passed through from the CI environment directly.
# These are platform-specific and cannot be abstracted by VERSIONING_* vars.

# Generate payload from template (only substitute specific variables)
PAYLOAD_FILE="/tmp/teams_payload.json"
# shellcheck disable=SC2016
VARS_TO_SUBSTITUTE='$NOTIFICATION_STYLE $NOTIFICATION_ICON $NOTIFICATION_TITLE $NOTIFICATION_SUBTITLE $BITBUCKET_REPO_SLUG $BITBUCKET_BRANCH $BITBUCKET_PR_ID $BITBUCKET_COMMIT_SHORT $BITBUCKET_PR_AUTHOR $BITBUCKET_WORKSPACE $BITBUCKET_BUILD_NUMBER'
envsubst "$VARS_TO_SUBSTITUTE" < "$PAYLOAD_TEMPLATE" > "$PAYLOAD_FILE"

# Send to Teams
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Content-Type: application/json" \
    -d @"$PAYLOAD_FILE" \
    "$TEAMS_WEBHOOK_URL")

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "202" ]; then
    echo "Teams notification sent successfully"
else
    echo "Warning: Teams notification failed with HTTP $HTTP_CODE"
fi
