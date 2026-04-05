#!/bin/sh
# ============================================================================
# Script: install-tools.sh
# Description: Install required tools for pipeline execution
# Inputs: None
# Outputs: Installed tools (git, curl, bash, jq, yq, openssh)
# ============================================================================

set -e

echo "Installing required tools..."

# Install Alpine packages
# gettext provides envsubst for template substitution in notifications
apk add --no-cache git curl bash openssh jq yq gettext

echo "✓ All tools installed successfully"
