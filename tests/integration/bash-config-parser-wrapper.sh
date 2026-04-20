#!/bin/sh
# Wrapper for dual-run testing: invokes config-parser.sh load_config() directly.
# Reads /workspace/.versioning.yml (if present) and produces /tmp/.versioning-merged.yml.
# Usage: docker run --rm -v /path/to/repo:/workspace -v /tmp:/tmp <image>
set -e
git config --global --add safe.directory /workspace
cd /workspace
. /pipe/lib/config-parser.sh
# load_config is called on source — output is already at MERGED_CONFIG (/tmp/.versioning-merged.yml)
