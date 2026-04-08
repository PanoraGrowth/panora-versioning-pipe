#!/usr/bin/env bash
# =============================================================================
# setup.bash — shared setup/teardown for all bats unit tests
#
# Provides:
#   common_setup    — creates isolated temp dir, git repo, MERGED_CONFIG
#   common_teardown — cleans up all temp state
#   source_config_parser <fixture> — loads a fixture config in isolation
# =============================================================================

PIPE_DIR="/pipe"
MERGED_CONFIG_LOCK="/tmp/.versioning-merged.lock"

# Create isolated test environment
# Each test gets its own temp dir, git repo, and MERGED_CONFIG path
common_setup() {
    BATS_TEST_TMPDIR="$(mktemp -d)"
    export BATS_TEST_TMPDIR

    # Isolated MERGED_CONFIG — critical for parallel test execution
    export MERGED_CONFIG="${BATS_TEST_TMPDIR}/.versioning-merged.yml"

    # Create a minimal git repo (config-parser needs find_repo_root)
    git init -q "${BATS_TEST_TMPDIR}/repo"
    git -C "${BATS_TEST_TMPDIR}/repo" config user.email "test@test.com"
    git -C "${BATS_TEST_TMPDIR}/repo" config user.name "Test"
    git -C "${BATS_TEST_TMPDIR}/repo" commit --allow-empty -m "init" -q
}

# Clean up all test state
common_teardown() {
    [ -d "${BATS_TEST_TMPDIR:-}" ] && rm -rf "$BATS_TEST_TMPDIR"
    # detect-scenario.sh writes here — clean it for safety
    rm -f /tmp/scenario.env
}

# Source config-parser.sh with an isolated fixture config
#
# Usage: source_config_parser "minimal"
#   Copies tests/fixtures/minimal.yml → .versioning.yml in the temp repo,
#   sources config-parser.sh, overrides MERGED_CONFIG to temp path,
#   then calls load_config.
#
# After this call, all config-parser getter functions are available
# and read from the isolated MERGED_CONFIG.
source_config_parser() {
    local fixture_name="$1"

    # Copy fixture as project config
    cp "${PIPE_DIR}/tests/fixtures/${fixture_name}.yml" \
       "${BATS_TEST_TMPDIR}/repo/.versioning.yml"

    # cd into the repo so find_repo_root() returns our temp path
    cd "${BATS_TEST_TMPDIR}/repo" || return 1

    # Lock during source: config-parser.sh auto-calls load_config() which writes
    # to the hardcoded /tmp/.versioning-merged.yml. We must hold the lock until
    # we override MERGED_CONFIG and re-run load_config to our isolated path.
    # shellcheck disable=SC1091
    exec 9>"$MERGED_CONFIG_LOCK"
    flock 9
    . "${PIPE_DIR}/lib/config-parser.sh"

    # Override MERGED_CONFIG to isolated path and re-run load_config
    # This is the key to parallel safety — load_config writes to $MERGED_CONFIG
    MERGED_CONFIG="${BATS_TEST_TMPDIR}/.versioning-merged.yml"
    export MERGED_CONFIG
    load_config
    flock -u 9
    exec 9>&-
}

# Write raw YAML content as a fixture (for inline/dynamic fixtures)
#
# Usage: write_inline_fixture "some: yaml\ncontent: here"
write_inline_fixture() {
    local content="$1"
    printf '%s\n' "$content" > "${BATS_TEST_TMPDIR}/repo/.versioning.yml"

    cd "${BATS_TEST_TMPDIR}/repo" || return 1

    # shellcheck disable=SC1091
    exec 9>"$MERGED_CONFIG_LOCK"
    flock 9
    . "${PIPE_DIR}/lib/config-parser.sh"

    MERGED_CONFIG="${BATS_TEST_TMPDIR}/.versioning-merged.yml"
    export MERGED_CONFIG
    load_config
    flock -u 9
    exec 9>&-
}
