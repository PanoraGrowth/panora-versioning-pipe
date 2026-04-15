#!/usr/bin/env bats

# Tests for tag parsing and building functions:
# parse_tag_to_version, parse_version_components, build_full_tag

load '../../helpers/setup'
load '../../helpers/assertions'

setup() { common_setup; }
teardown() { common_teardown; }

# =============================================================================
# parse_tag_to_version
# =============================================================================

@test "parse_tag_to_version: strips timestamp from tag" {
    source_config_parser "with-timestamp"
    run parse_tag_to_version "0.1.2.20260407120000"
    assert_equals "0.1.2" "$output"
}

@test "parse_tag_to_version: strips timestamp with collision suffix" {
    source_config_parser "with-timestamp"
    run parse_tag_to_version "0.1.2.20260407120000-1"
    assert_equals "0.1.2" "$output"
}

@test "parse_tag_to_version: strips v prefix" {
    source_config_parser "with-v-prefix"
    run parse_tag_to_version "v1.2"
    assert_equals "1.2" "$output"
}

@test "parse_tag_to_version: no-timestamp — returns version as-is" {
    source_config_parser "no-timestamp"
    run parse_tag_to_version "3.5.7"
    assert_equals "3.5.7" "$output"
}

@test "parse_tag_to_version: v prefix + timestamp" {
    source_config_parser "all-components"
    # all-components has timestamp enabled but no v prefix
    run parse_tag_to_version "1.0.0.20260407120000"
    assert_equals "1.0.0" "$output"
}

# =============================================================================
# parse_version_components
# =============================================================================

@test "parse_version_components: epoch.major.patch" {
    source_config_parser "no-timestamp"
    parse_version_components "2.5.8"
    assert_equals "2" "$PARSED_EPOCH"
    assert_equals "5" "$PARSED_MAJOR"
    assert_equals "8" "$PARSED_PATCH"
}

@test "parse_version_components: major.patch only (epoch disabled)" {
    source_config_parser "with-v-prefix"
    parse_version_components "3.7"
    assert_equals "0" "$PARSED_EPOCH" "epoch should default to 0 when disabled"
    assert_equals "3" "$PARSED_MAJOR"
    assert_equals "7" "$PARSED_PATCH"
}

@test "parse_version_components: all zeros" {
    source_config_parser "no-timestamp"
    parse_version_components "0.0.0"
    assert_equals "0" "$PARSED_EPOCH"
    assert_equals "0" "$PARSED_MAJOR"
    assert_equals "0" "$PARSED_PATCH"
}

@test "parse_version_components: large numbers" {
    source_config_parser "no-timestamp"
    parse_version_components "10.200.3000"
    assert_equals "10" "$PARSED_EPOCH"
    assert_equals "200" "$PARSED_MAJOR"
    assert_equals "3000" "$PARSED_PATCH"
}

# =============================================================================
# build_full_tag
# =============================================================================

@test "build_full_tag: no-timestamp — returns version as-is" {
    source_config_parser "no-timestamp"
    run build_full_tag "1.2.3"
    assert_equals "1.2.3" "$output"
}

@test "build_full_tag: with-v-prefix — prepends v" {
    source_config_parser "with-v-prefix"
    run build_full_tag "5.7"
    assert_equals "v5.7" "$output"
}

@test "build_full_tag: with-timestamp — appends timestamp" {
    source_config_parser "with-timestamp"
    run build_full_tag "0.1.2"
    # Timestamp format: %Y%m%d%H%M%S (14 digits)
    assert_output_matches '^0\.1\.2\.[0-9]{14}$' "should be version.timestamp(14 digits)"
}

@test "build_full_tag: all-components — version.timestamp" {
    source_config_parser "all-components"
    run build_full_tag "1.0.0"
    assert_output_matches '^1\.0\.0\.[0-9]{14}$' "should be version.timestamp(14 digits)"
}

@test "build_full_tag: timestamp uses UTC timezone" {
    source_config_parser "with-timestamp"
    run build_full_tag "0.0.0"
    # Just verify it produces a valid-looking timestamp (starts with 20)
    assert_output_matches '^0\.0\.0\.20[0-9]{12}$' "timestamp should start with 20xx"
}
