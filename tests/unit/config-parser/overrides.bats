#!/usr/bin/env bats

# overrides.bats — tests for commit_type_overrides (apply_commit_type_overrides)
# Uses custom-types.yml fixture which:
#   - Patches feat emoji to 🆕
#   - Changes docs bump to "none"
#   - Adds new type "infra" with bump=minor, emoji=🔩

load '../../helpers/setup'
load '../../helpers/assertions'

setup() { common_setup; }
teardown() { common_teardown; }

# =============================================================================
# PATCH EXISTING TYPE — emoji change
# =============================================================================

@test "override: feat emoji changed to 🆕" {
    source_config_parser "custom-types"
    run get_commit_type_emoji "feat"
    assert_equals "🆕" "$output"
}

@test "override: feat bump unchanged (still major)" {
    source_config_parser "custom-types"
    run get_bump_action "feat"
    assert_equals "major" "$output"
}

# =============================================================================
# PATCH EXISTING TYPE — bump change
# =============================================================================

@test "override: docs bump changed to none" {
    source_config_parser "custom-types"
    run get_bump_action "docs"
    assert_equals "none" "$output"
}

@test "override: docs emoji unchanged (still 📚)" {
    source_config_parser "custom-types"
    run get_commit_type_emoji "docs"
    assert_equals "📚" "$output"
}

# =============================================================================
# ADD NEW TYPE
# =============================================================================

@test "override: infra type exists in commit types pattern" {
    source_config_parser "custom-types"
    run get_commit_types_pattern
    assert_output_matches "infra"
}

@test "override: infra bump is minor" {
    source_config_parser "custom-types"
    run get_bump_action "infra"
    assert_equals "minor" "$output"
}

@test "override: infra emoji is 🔩" {
    source_config_parser "custom-types"
    run get_commit_type_emoji "infra"
    assert_equals "🔩" "$output"
}

@test "override: infra appears in minor bump types" {
    source_config_parser "custom-types"
    run get_types_for_bump "minor"
    assert_output_matches "infra"
}

# =============================================================================
# NON-OVERRIDDEN TYPES UNAFFECTED
# =============================================================================

@test "override: fix unchanged (bump still minor)" {
    source_config_parser "custom-types"
    run get_bump_action "fix"
    assert_equals "minor" "$output"
}

@test "override: fix unchanged (emoji still 🐛)" {
    source_config_parser "custom-types"
    run get_commit_type_emoji "fix"
    assert_equals "🐛" "$output"
}

@test "override: chore unchanged (bump still minor)" {
    source_config_parser "custom-types"
    run get_bump_action "chore"
    assert_equals "minor" "$output"
}

# =============================================================================
# NO OVERRIDES — baseline
# =============================================================================

@test "no overrides: minimal fixture feat emoji is default 🚀" {
    source_config_parser "minimal"
    run get_commit_type_emoji "feat"
    assert_equals "🚀" "$output"
}

@test "no overrides: minimal fixture docs bump is default minor" {
    source_config_parser "minimal"
    run get_bump_action "docs"
    assert_equals "minor" "$output"
}

@test "no overrides: minimal fixture has no infra type" {
    source_config_parser "minimal"
    run get_bump_action "infra"
    assert_equals "none" "$output"
}
