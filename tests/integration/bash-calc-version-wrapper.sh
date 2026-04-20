#!/bin/sh
# Wrapper for dual-run testing: sets safe.directory so git works when the
# workspace is mounted from a host user with a different UID than the container
# user (pipe, uid 1001). pipe.sh normally handles this via configure-git.sh,
# but the dual-run invokes calculate-version.sh directly and bypasses that step.
set -e
git config --global --add safe.directory /workspace 2>/dev/null || true
exec /pipe/versioning/calculate-version.sh "$@"
