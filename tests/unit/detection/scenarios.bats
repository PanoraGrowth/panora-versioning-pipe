#!/usr/bin/env bats

# Tests for detect-scenario.sh — runs as subprocess (not sourced)
# Validates all 7 scenarios based on VERSIONING_BRANCH + VERSIONING_TARGET_BRANCH
#
# detect-scenario.sh sources config-parser.sh which auto-calls load_config() and
# writes to the hardcoded /tmp/.versioning-merged.yml. With --jobs 4, other test
# files (config-parser tests) also write to this path when sourcing config-parser.sh.
# We use flock to serialize access and prevent race conditions.

load '../../helpers/setup'
load '../../helpers/assertions'

LOCKFILE="/tmp/.versioning-merged.lock"

setup() { common_setup; }
teardown() { common_teardown; }

# Helper: run detect-scenario.sh with given branches, serialized via flock.
# Emits the script stdout AND the final scenario.env content — both captured
# inside the lock so parallel jobs cannot race on /tmp/scenario.env.
run_detect() {
    local fixture="$1"
    local source_branch="$2"
    local target_branch="$3"

    cp "${PIPE_DIR}/tests/fixtures/${fixture}.yml" \
       "${BATS_TEST_TMPDIR}/repo/.versioning.yml"

    cd "${BATS_TEST_TMPDIR}/repo" || return 1

    # flock serializes access to /tmp/.versioning-merged.yml and /tmp/scenario.env
    # across parallel jobs. scenario.env is read INSIDE the lock to prevent another
    # job overwriting it between the script finishing and our read.
    run flock "$LOCKFILE" sh -c "
        VERSIONING_BRANCH='$source_branch' \
        VERSIONING_TARGET_BRANCH='$target_branch' \
        sh '${PIPE_DIR}/detection/detect-scenario.sh' ; \
        echo SCENARIO_ENV=\$(grep '^SCENARIO=' /tmp/scenario.env 2>/dev/null | head -1)
    "
}

# Helper: assert that run_detect captured the expected scenario in its output.
# Uses $output (captured inside the flock) instead of reading /tmp/scenario.env
# directly — which would be a race under --jobs N.
assert_scenario() {
    local expected="$1"
    echo "$output" | grep -q "SCENARIO_ENV=SCENARIO=${expected}"
}

# --- Minimal fixture (default branches: development, pre-production, main) ---

@test "scenario: development_release — feature to development" {
    run_detect "minimal" "feature/login" "development"
    [ "$status" -eq 0 ]
    assert_output_matches "Development Release"
    assert_scenario "development_release"
}

@test "scenario: hotfix (preprod target) — hotfix to pre-production" {
    run_detect "minimal" "hotfix/urgent-fix" "pre-production"
    [ "$status" -eq 0 ]
    assert_output_matches "Hotfix to Pre-production"
    assert_scenario "hotfix"
}

@test "scenario: promotion_to_preprod — development to pre-production" {
    run_detect "minimal" "development" "pre-production"
    [ "$status" -eq 0 ]
    assert_output_matches "Promotion to Pre-production"
    assert_scenario "promotion_to_preprod"
}

@test "scenario: hotfix (main target) — hotfix to main" {
    run_detect "minimal" "hotfix/critical" "main"
    [ "$status" -eq 0 ]
    assert_output_matches "Hotfix to Production"
    assert_scenario "hotfix"
}

@test "scenario: promotion_to_main — pre-production to main" {
    run_detect "minimal" "pre-production" "main"
    [ "$status" -eq 0 ]
    assert_output_matches "Promotion to Production"
    assert_scenario "promotion_to_main"
}

@test "scenario: development_release (direct) — feature to main" {
    run_detect "minimal" "feature/quick-fix" "main"
    [ "$status" -eq 0 ]
    assert_output_matches "Direct to Main Release"
    assert_scenario "development_release"
}

@test "scenario: unknown — feature to random branch" {
    run_detect "minimal" "feature/x" "release/v2"
    [ "$status" -eq 0 ]
    assert_output_matches "Unknown"
    assert_scenario "unknown"
}

# --- Custom-branches fixture (dev, staging, master, emergency/) ---

@test "custom-branches: development_release — feature to dev" {
    run_detect "custom-branches" "feature/login" "dev"
    [ "$status" -eq 0 ]
    assert_output_matches "Development Release"
    assert_scenario "development_release"
}

@test "custom-branches: hotfix (staging target) — hotfix to staging" {
    # custom-branches.yml sets branches but NOT hotfix.keyword,
    # so hotfix keyword remains the default "hotfix" (matches branch "hotfix/*")
    run_detect "custom-branches" "hotfix/db-crash" "staging"
    [ "$status" -eq 0 ]
    assert_output_matches "Hotfix to Pre-production"
    assert_scenario "hotfix"
}

@test "custom-branches: promotion_to_main — staging to master" {
    run_detect "custom-branches" "staging" "master"
    [ "$status" -eq 0 ]
    assert_output_matches "Promotion to Production"
    assert_scenario "promotion_to_main"
}

@test "custom-branches: hotfix (master target) — hotfix to master" {
    # hotfix keyword default "hotfix" matches branch prefix "hotfix/"
    run_detect "custom-branches" "hotfix/urgent" "master"
    [ "$status" -eq 0 ]
    assert_output_matches "Hotfix to Production"
    assert_scenario "hotfix"
}

@test "custom-branches: unknown — feature to pre-production (not configured)" {
    run_detect "custom-branches" "feature/x" "pre-production"
    [ "$status" -eq 0 ]
    assert_output_matches "Unknown"
    assert_scenario "unknown"
}
