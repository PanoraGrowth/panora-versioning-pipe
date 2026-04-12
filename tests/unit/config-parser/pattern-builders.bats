#!/usr/bin/env bats

# Tests for pattern builder functions:
# get_tag_pattern, build_version_string, build_ticket_prefix_pattern,
# build_ticket_full_pattern, build_bump_pattern

load '../../helpers/setup'
load '../../helpers/assertions'

setup() { common_setup; }
teardown() { common_teardown; }

# =============================================================================
# get_tag_pattern
# =============================================================================

@test "get_tag_pattern: no-timestamp fixture — no timestamp, optional patch" {
    # v0.6.3+: defaults.yml has patch.enabled: true, so the optional patch
    # group (\.[0-9]+)? appears in the pattern for fixtures that don't
    # explicitly opt out.
    source_config_parser "no-timestamp"
    run get_tag_pattern
    assert_equals '^[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?$' "$output"
}

@test "get_tag_pattern: with-timestamp fixture — includes timestamp group + optional patch" {
    source_config_parser "with-timestamp"
    run get_tag_pattern
    assert_equals '^[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?\.[0-9]{12,14}(-[0-9]+)?$' "$output"
}

@test "get_tag_pattern: with-v-prefix fixture — starts with v, no timestamp, optional patch" {
    source_config_parser "with-v-prefix"
    run get_tag_pattern
    assert_equals '^v[0-9]+\.[0-9]+(\.[0-9]+)?$' "$output"
}

@test "get_tag_pattern: all-components fixture — period+major+minor+timestamp + optional patch" {
    source_config_parser "all-components"
    run get_tag_pattern
    assert_equals '^[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?\.[0-9]{12,14}(-[0-9]+)?$' "$output"
}

@test "get_tag_pattern: patch-disabled fixture — no optional patch group" {
    # Consumer explicitly opts out of patch. Pattern should NOT contain
    # the optional patch group.
    source_config_parser "patch-disabled"
    run get_tag_pattern
    assert_equals '^[0-9]+\.[0-9]+$' "$output"
}

# =============================================================================
# build_version_string
# =============================================================================

@test "build_version_string: no-timestamp — period.major.minor" {
    source_config_parser "no-timestamp"
    run build_version_string 1 2 3
    assert_equals "1.2.3" "$output"
}

@test "build_version_string: with-v-prefix — major.minor only (period disabled)" {
    source_config_parser "with-v-prefix"
    run build_version_string 0 5 7
    assert_equals "5.7" "$output"
}

@test "build_version_string: all-components — period.major.minor" {
    source_config_parser "all-components"
    run build_version_string 2 4 6
    assert_equals "2.4.6" "$output"
}

@test "build_version_string: zeros produce valid string" {
    source_config_parser "no-timestamp"
    run build_version_string 0 0 0
    assert_equals "0.0.0" "$output"
}

# =============================================================================
# build_ticket_prefix_pattern
# =============================================================================

@test "build_ticket_prefix_pattern: ticket-based — returns prefix pattern" {
    source_config_parser "ticket-based"
    run build_ticket_prefix_pattern
    assert_equals '^(AM|TECH)-[0-9]+ - ' "$output"
}

@test "build_ticket_prefix_pattern: conventional — returns empty" {
    source_config_parser "conventional-full"
    run build_ticket_prefix_pattern
    assert_empty "$output"
}

@test "build_ticket_prefix_pattern: minimal (no prefixes) — returns empty" {
    source_config_parser "minimal"
    run build_ticket_prefix_pattern
    assert_empty "$output"
}

# =============================================================================
# build_ticket_full_pattern
# =============================================================================

@test "build_ticket_full_pattern: ticket-based — includes prefixes and types" {
    source_config_parser "ticket-based"
    run build_ticket_full_pattern
    # Should contain AM|TECH prefix group and type group
    assert_output_matches '^\^' "should start with ^"
    assert_output_matches 'AM\|TECH' "should contain ticket prefixes"
    assert_output_matches 'feat' "should contain feat type"
    assert_output_matches 'fix' "should contain fix type"
}

@test "build_ticket_full_pattern: conventional — type(scope)?: format" {
    source_config_parser "conventional-full"
    run build_ticket_full_pattern
    assert_output_matches '^\^\(' "should start with ^("
    assert_output_matches 'feat' "should contain feat type"
    # The output contains literal backslash-parens: (\(.+\))?
    [[ "$output" == *'(\(.+\))?:'* ]]
}

@test "build_ticket_full_pattern: minimal (ticket, no prefixes) — fallback pattern" {
    source_config_parser "minimal"
    run build_ticket_full_pattern
    # No prefixes: pattern uses fallback "^.* - (types):|^(types):"
    assert_output_matches 'feat' "should contain feat type"
    assert_output_matches '\.\*' "should have .* wildcard for no-prefix"
}

# =============================================================================
# build_bump_pattern
# =============================================================================

@test "build_bump_pattern: major bump — conventional config" {
    source_config_parser "conventional-full"
    run build_bump_pattern "major"
    # major bump types: major, feat, feature, breaking
    assert_output_matches 'feat' "should contain feat"
    assert_output_matches 'major' "should contain major"
    assert_output_matches 'breaking' "should contain breaking"
}

@test "build_bump_pattern: minor bump — conventional config" {
    source_config_parser "conventional-full"
    run build_bump_pattern "minor"
    assert_output_matches 'fix' "should contain fix"
    assert_output_matches 'refactor' "should contain refactor"
}

@test "build_bump_pattern: nonexistent bump type — returns empty" {
    source_config_parser "conventional-full"
    run build_bump_pattern "nonexistent"
    assert_empty "$output"
}

@test "build_bump_pattern: major bump — ticket-based includes prefixes" {
    source_config_parser "ticket-based"
    run build_bump_pattern "major"
    assert_output_matches 'AM\|TECH' "should contain ticket prefixes"
    assert_output_matches 'feat' "should contain feat"
}
