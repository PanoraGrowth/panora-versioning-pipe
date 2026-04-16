#!/usr/bin/env bats

# hotfix-counter-component.bats — tests for the HOTFIX_COUNTER version component in config-parser.sh
#
# Covers: is_component_enabled "hotfix_counter", get_component_initial "hotfix_counter",
# build_version_string with the 4th arg, parse_version_components setting
# PARSED_HOTFIX_COUNTER, and get_tag_pattern rendering the optional hotfix_counter group.

load '../../helpers/setup'
load '../../helpers/assertions'

setup() { common_setup; }
teardown() { common_teardown; }

# =============================================================================
# is_component_enabled "hotfix_counter"
# =============================================================================

@test "hotfix_counter component: enabled by default (minimal fixture, v0.6.3+)" {
    # v0.6.3 flipped the default of hotfix_counter.enabled from false → true. The
    # minimal fixture inherits defaults, so the component is now enabled.
    source_config_parser "minimal"
    run is_component_enabled "hotfix_counter"
    [ "$status" -eq 0 ]
}

@test "hotfix_counter component: disabled when explicitly opted out (hotfix-counter-disabled fixture)" {
    source_config_parser "hotfix-counter-disabled"
    run is_component_enabled "hotfix_counter"
    [ "$status" -ne 0 ]
}

@test "hotfix_counter component: enabled when with-hotfix-counter fixture opts in explicitly" {
    source_config_parser "with-hotfix-counter"
    run is_component_enabled "hotfix_counter"
    [ "$status" -eq 0 ]
}

# =============================================================================
# build_version_string — hotfix_counter rendering rules
# =============================================================================

@test "build_version_string: omits hotfix_counter when hotfix_counter=0 (backward compat)" {
    source_config_parser "with-hotfix-counter"
    run build_version_string "0" "5" "9" "0"
    assert_equals "0.5.9" "$output"
}

@test "build_version_string: omits hotfix_counter entirely when hotfix_counter.enabled=false" {
    source_config_parser "hotfix-counter-disabled"
    # Even when a positive hotfix_counter arg is passed, disabled component means no render
    run build_version_string "0" "5" "9" "7"
    # hotfix-counter-disabled fixture has epoch=off, major+patch=on, hotfix_counter=off
    assert_equals "5.9" "$output"
}

@test "build_version_string: appends .1 when hotfix_counter=1 and enabled" {
    source_config_parser "with-hotfix-counter"
    run build_version_string "0" "5" "9" "1"
    assert_equals "0.5.9.1" "$output"
}

@test "build_version_string: appends .2 when hotfix_counter=2 and enabled" {
    source_config_parser "with-hotfix-counter"
    run build_version_string "0" "5" "9" "2"
    assert_equals "0.5.9.2" "$output"
}

@test "build_version_string: patch=0 renders as .0 (SemVer compliant)" {
    # patch=0 must always render — no numeric gate on the patch slot.
    # v0.5.0 is a valid SemVer tag; omitting the zero would produce v0.5 which is wrong.
    source_config_parser "with-hotfix-counter"
    run build_version_string "0" "5" "0" "0"
    assert_equals "0.5.0" "$output"
}

@test "build_version_string: patch=0 with hotfix_counter=0 — only patch renders (SemVer compliant)" {
    # hotfix_counter=0 is still omitted; patch=0 is still included.
    source_config_parser "with-hotfix-counter"
    run build_version_string "0" "12" "0" "0"
    assert_equals "0.12.0" "$output"
}

# =============================================================================
# parse_version_components — PARSED_HOTFIX_COUNTER global
# =============================================================================

@test "parse_version_components: v0.5.9 → PARSED_HOTFIX_COUNTER=0 (absent)" {
    source_config_parser "with-hotfix-counter"
    VERSION=$(parse_tag_to_version "v0.5.9")
    parse_version_components "$VERSION"
    assert_equals "5" "$PARSED_MAJOR"
    assert_equals "9" "$PARSED_PATCH"
    assert_equals "0" "$PARSED_HOTFIX_COUNTER"
}

@test "parse_version_components: v0.5.0 → PARSED_PATCH=0 (SemVer compliant round-trip)" {
    # Tags with patch=0 must parse back correctly — v0.5.0 is a valid SemVer tag.
    source_config_parser "with-hotfix-counter"
    VERSION=$(parse_tag_to_version "v0.5.0")
    parse_version_components "$VERSION"
    assert_equals "0" "$PARSED_EPOCH"
    assert_equals "5" "$PARSED_MAJOR"
    assert_equals "0" "$PARSED_PATCH"
    assert_equals "0" "$PARSED_HOTFIX_COUNTER"
}

@test "parse_version_components: v0.5.9.1 → PARSED_HOTFIX_COUNTER=1" {
    source_config_parser "with-hotfix-counter"
    VERSION=$(parse_tag_to_version "v0.5.9.1")
    parse_version_components "$VERSION"
    assert_equals "5" "$PARSED_MAJOR"
    assert_equals "9" "$PARSED_PATCH"
    assert_equals "1" "$PARSED_HOTFIX_COUNTER"
}

@test "parse_version_components: v0.5.9.123 → PARSED_HOTFIX_COUNTER=123" {
    source_config_parser "with-hotfix-counter"
    VERSION=$(parse_tag_to_version "v0.5.9.123")
    parse_version_components "$VERSION"
    assert_equals "123" "$PARSED_HOTFIX_COUNTER"
}

@test "parse_version_components: bare 0.5.9 (no v prefix) → PARSED_HOTFIX_COUNTER=0" {
    source_config_parser "with-hotfix-counter"
    VERSION=$(parse_tag_to_version "0.5.9")
    parse_version_components "$VERSION"
    assert_equals "0" "$PARSED_HOTFIX_COUNTER"
}

# =============================================================================
# get_tag_pattern — optional hotfix_counter group
# =============================================================================

@test "get_tag_pattern: matches both v0.5.9 and v0.5.9.1 when hotfix_counter enabled" {
    source_config_parser "with-hotfix-counter"
    TAG_PATTERN=$(get_tag_pattern)
    # Both tags must match the same regex so git tag filtering sees both forms
    echo "v0.5.9" | grep -qE "$TAG_PATTERN"
    echo "v0.5.9.1" | grep -qE "$TAG_PATTERN"
    echo "v0.5.9.123" | grep -qE "$TAG_PATTERN"
    # Sanity — non-tag strings should not match
    ! echo "v0.5" | grep -qE "$TAG_PATTERN"
}
