#!/usr/bin/env bats

# patch-component.bats — tests for the PATCH version component in config-parser.sh
#
# Covers: is_component_enabled "patch", get_component_initial "patch",
# build_version_string with the 4th arg, parse_version_components setting
# PARSED_PATCH, and get_tag_pattern rendering the optional patch group.

load '../../helpers/setup'
load '../../helpers/assertions'

setup() { common_setup; }
teardown() { common_teardown; }

# =============================================================================
# is_component_enabled "patch"
# =============================================================================

@test "patch component: enabled by default (minimal fixture, v0.6.3+)" {
    # v0.6.3 flipped the default of patch.enabled from false → true. The
    # minimal fixture inherits defaults, so the component is now enabled.
    source_config_parser "minimal"
    run is_component_enabled "patch"
    [ "$status" -eq 0 ]
}

@test "patch component: disabled when explicitly opted out (patch-disabled fixture)" {
    source_config_parser "patch-disabled"
    run is_component_enabled "patch"
    [ "$status" -ne 0 ]
}

@test "patch component: enabled when with-patch fixture opts in explicitly" {
    source_config_parser "with-patch"
    run is_component_enabled "patch"
    [ "$status" -eq 0 ]
}

# =============================================================================
# build_version_string — patch rendering rules
# =============================================================================

@test "build_version_string: omits patch when patch=0 (backward compat)" {
    source_config_parser "with-patch"
    run build_version_string "0" "5" "9" "0"
    assert_equals "0.5.9" "$output"
}

@test "build_version_string: omits patch entirely when patch.enabled=false" {
    source_config_parser "patch-disabled"
    # Even when a positive patch arg is passed, disabled component means no render
    run build_version_string "0" "5" "9" "7"
    # patch-disabled fixture has epoch=off, major+minor=on, patch=off
    assert_equals "5.9" "$output"
}

@test "build_version_string: appends .1 when patch=1 and enabled" {
    source_config_parser "with-patch"
    run build_version_string "0" "5" "9" "1"
    assert_equals "0.5.9.1" "$output"
}

@test "build_version_string: appends .2 when patch=2 and enabled" {
    source_config_parser "with-patch"
    run build_version_string "0" "5" "9" "2"
    assert_equals "0.5.9.2" "$output"
}

# =============================================================================
# parse_version_components — PARSED_PATCH global
# =============================================================================

@test "parse_version_components: v0.5.9 → PARSED_PATCH=0 (absent)" {
    source_config_parser "with-patch"
    VERSION=$(parse_tag_to_version "v0.5.9")
    parse_version_components "$VERSION"
    assert_equals "5" "$PARSED_MAJOR"
    assert_equals "9" "$PARSED_MINOR"
    assert_equals "0" "$PARSED_PATCH"
}

@test "parse_version_components: v0.5.9.1 → PARSED_PATCH=1" {
    source_config_parser "with-patch"
    VERSION=$(parse_tag_to_version "v0.5.9.1")
    parse_version_components "$VERSION"
    assert_equals "5" "$PARSED_MAJOR"
    assert_equals "9" "$PARSED_MINOR"
    assert_equals "1" "$PARSED_PATCH"
}

@test "parse_version_components: v0.5.9.123 → PARSED_PATCH=123" {
    source_config_parser "with-patch"
    VERSION=$(parse_tag_to_version "v0.5.9.123")
    parse_version_components "$VERSION"
    assert_equals "123" "$PARSED_PATCH"
}

@test "parse_version_components: bare 0.5.9 (no v prefix) → PARSED_PATCH=0" {
    source_config_parser "with-patch"
    VERSION=$(parse_tag_to_version "0.5.9")
    parse_version_components "$VERSION"
    assert_equals "0" "$PARSED_PATCH"
}

# =============================================================================
# get_tag_pattern — optional patch group
# =============================================================================

@test "get_tag_pattern: matches both v0.5.9 and v0.5.9.1 when patch enabled" {
    source_config_parser "with-patch"
    TAG_PATTERN=$(get_tag_pattern)
    # Both tags must match the same regex so git tag filtering sees both forms
    echo "v0.5.9" | grep -qE "$TAG_PATTERN"
    echo "v0.5.9.1" | grep -qE "$TAG_PATTERN"
    echo "v0.5.9.123" | grep -qE "$TAG_PATTERN"
    # Sanity — non-tag strings should not match
    ! echo "v0.5" | grep -qE "$TAG_PATTERN"
}
