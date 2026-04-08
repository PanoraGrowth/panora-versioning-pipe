#!/usr/bin/env bats

# Smoke test — validates that test infrastructure works:
# - helpers load correctly
# - source_config_parser loads a fixture
# - getter functions work
# - MERGED_CONFIG isolation works

load '../../helpers/setup'
load '../../helpers/assertions'

setup() { common_setup; }
teardown() { common_teardown; }

@test "source_config_parser loads minimal fixture" {
    source_config_parser "minimal"
    [ -f "$MERGED_CONFIG" ]
}

@test "get_commits_format returns ticket with minimal fixture" {
    source_config_parser "minimal"
    run get_commits_format
    assert_equals "ticket" "$output"
}

@test "get_commits_format returns conventional with conventional-full fixture" {
    source_config_parser "conventional-full"
    run get_commits_format
    assert_equals "conventional" "$output"
}

@test "MERGED_CONFIG is isolated per test (not /tmp)" {
    source_config_parser "minimal"
    [[ "$MERGED_CONFIG" == *"$BATS_TEST_TMPDIR"* ]]
    [[ "$MERGED_CONFIG" != "/tmp/.versioning-merged.yml" ]]
}
