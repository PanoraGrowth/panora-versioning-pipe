#!/usr/bin/env bats

# notifications.bats — tests for notify-teams.sh gate logic
#
# notify-teams.sh reads its config via REPO_ROOT (derived from SCRIPT_DIR),
# which in the test container is /pipe (read-only). Custom .versioning.yml
# overrides cannot be injected from unit tests. All tests exercise the script
# against the built-in defaults.yml values:
#   enabled: true, on_success: false, on_failure: true
#
# Coverage tested here:
# - Invalid trigger type → non-zero exit
# - on_success: false (default) + trigger "success" → "disabled" early exit
# - on_failure: true (default) + trigger "failure" + no webhook → skip warning
# - Missing TEAMS_WEBHOOK_URL → exits 0 (not an error)

load '../../helpers/setup'
load '../../helpers/assertions'

LOCKFILE="/tmp/.versioning-merged.lock"
NOTIFY_SCRIPT="/pipe/reporting/notify-teams.sh"

setup() { common_setup; }
teardown() { common_teardown; }

# =============================================================================
# Input validation
# =============================================================================

@test "missing trigger type argument — exits non-zero with usage message" {
    run sh "${NOTIFY_SCRIPT}"
    [ "$status" -ne 0 ]
}

@test "invalid trigger type — exits non-zero with error message" {
    run sh "${NOTIFY_SCRIPT}" "invalid"
    [ "$status" -ne 0 ]
}

# =============================================================================
# Default config behaviour (defaults.yml: enabled=true, on_success=false,
# on_failure=true)
# =============================================================================

@test "on_success: false (default) — success trigger exits 0 with disabled message" {
    run flock "$LOCKFILE" sh -c "
        unset TEAMS_WEBHOOK_URL ;
        sh '${NOTIFY_SCRIPT}' 'success' 2>&1
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"disabled"* ]]
}

@test "on_failure: true (default) — failure trigger without webhook exits 0 (skip warning)" {
    run flock "$LOCKFILE" sh -c "
        unset TEAMS_WEBHOOK_URL ;
        sh '${NOTIFY_SCRIPT}' 'failure' 2>&1
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"TEAMS_WEBHOOK_URL not configured"* ]]
}

@test "TEAMS_WEBHOOK_URL empty string — treated as unset, exits 0 with skip warning" {
    run flock "$LOCKFILE" sh -c "
        TEAMS_WEBHOOK_URL='' ;
        export TEAMS_WEBHOOK_URL ;
        sh '${NOTIFY_SCRIPT}' 'failure' 2>&1
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"TEAMS_WEBHOOK_URL not configured"* ]]
}
