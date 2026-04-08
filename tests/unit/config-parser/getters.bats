#!/usr/bin/env bats

# getters.bats — tests for ALL config-parser.sh getter functions
# Uses fixtures from tests/fixtures/ to validate each getter against known values

load '../../helpers/setup'
load '../../helpers/assertions'

setup() { common_setup; }
teardown() { common_teardown; }

# =============================================================================
# COMMITS FORMAT
# =============================================================================

@test "get_commits_format: minimal fixture returns ticket" {
    source_config_parser "minimal"
    run get_commits_format
    assert_equals "ticket" "$output"
}

@test "get_commits_format: conventional-full fixture returns conventional" {
    source_config_parser "conventional-full"
    run get_commits_format
    assert_equals "conventional" "$output"
}

@test "is_conventional_commits: true for conventional-full" {
    source_config_parser "conventional-full"
    run is_conventional_commits
    [ "$status" -eq 0 ]
}

@test "is_conventional_commits: false for minimal (ticket)" {
    source_config_parser "minimal"
    run is_conventional_commits
    [ "$status" -ne 0 ]
}

# =============================================================================
# TICKET CONFIGURATION
# =============================================================================

@test "get_ticket_prefixes_pattern: ticket-based returns AM|TECH" {
    source_config_parser "ticket-based"
    run get_ticket_prefixes_pattern
    assert_equals "AM|TECH" "$output"
}

@test "get_ticket_prefixes_pattern: minimal returns empty (no prefixes)" {
    source_config_parser "minimal"
    run get_ticket_prefixes_pattern
    assert_empty "$output"
}

@test "has_ticket_prefixes: true for ticket-based" {
    source_config_parser "ticket-based"
    run has_ticket_prefixes
    [ "$status" -eq 0 ]
}

@test "has_ticket_prefixes: false for minimal" {
    source_config_parser "minimal"
    run has_ticket_prefixes
    [ "$status" -ne 0 ]
}

@test "is_ticket_required: true for ticket-based" {
    source_config_parser "ticket-based"
    run is_ticket_required
    [ "$status" -eq 0 ]
}

@test "is_ticket_required: false for minimal (default)" {
    source_config_parser "minimal"
    run is_ticket_required
    [ "$status" -ne 0 ]
}

@test "get_ticket_url: ticket-based returns configured URL" {
    source_config_parser "ticket-based"
    run get_ticket_url
    assert_equals "https://tickets.example.com" "$output"
}

@test "get_ticket_url: minimal returns empty (default)" {
    source_config_parser "minimal"
    run get_ticket_url
    assert_empty "$output"
}

# =============================================================================
# VERSION COMPONENTS
# =============================================================================

@test "is_component_enabled period: true for all-components" {
    source_config_parser "all-components"
    run is_component_enabled "period"
    [ "$status" -eq 0 ]
}

@test "is_component_enabled period: false for with-v-prefix" {
    source_config_parser "with-v-prefix"
    run is_component_enabled "period"
    [ "$status" -ne 0 ]
}

@test "is_component_enabled major: true for all-components" {
    source_config_parser "all-components"
    run is_component_enabled "major"
    [ "$status" -eq 0 ]
}

@test "is_component_enabled minor: true for all-components" {
    source_config_parser "all-components"
    run is_component_enabled "minor"
    [ "$status" -eq 0 ]
}

@test "is_component_enabled timestamp: true for with-timestamp" {
    source_config_parser "with-timestamp"
    run is_component_enabled "timestamp"
    [ "$status" -eq 0 ]
}

@test "is_component_enabled timestamp: false for no-timestamp" {
    source_config_parser "no-timestamp"
    run is_component_enabled "timestamp"
    [ "$status" -ne 0 ]
}

@test "get_component_initial: period initial is 1 for all-components" {
    source_config_parser "all-components"
    run get_component_initial "period" "0"
    assert_equals "1" "$output"
}

@test "get_component_initial: major initial is 0 for all-components" {
    source_config_parser "all-components"
    run get_component_initial "major" "0"
    assert_equals "0" "$output"
}

@test "get_component_initial: minor initial is 0 for all-components" {
    source_config_parser "all-components"
    run get_component_initial "minor" "0"
    assert_equals "0" "$output"
}

# =============================================================================
# VERSION SEPARATORS & PREFIX
# =============================================================================

@test "get_version_separator: default is dot" {
    source_config_parser "minimal"
    run get_version_separator
    assert_equals "." "$output"
}

@test "get_timestamp_separator: default is dot" {
    source_config_parser "minimal"
    run get_timestamp_separator
    assert_equals "." "$output"
}

@test "get_tag_suffix: default is empty" {
    source_config_parser "minimal"
    run get_tag_suffix
    assert_empty "$output"
}

@test "get_timestamp_format: with-timestamp returns configured format" {
    source_config_parser "with-timestamp"
    run get_timestamp_format
    assert_equals "%Y%m%d%H%M%S" "$output"
}

@test "get_timezone: with-timestamp returns UTC" {
    source_config_parser "with-timestamp"
    run get_timezone
    assert_equals "UTC" "$output"
}

@test "use_tag_prefix_v: true for with-v-prefix" {
    source_config_parser "with-v-prefix"
    run use_tag_prefix_v
    [ "$status" -eq 0 ]
}

@test "use_tag_prefix_v: false for minimal (default)" {
    source_config_parser "minimal"
    run use_tag_prefix_v
    [ "$status" -ne 0 ]
}

@test "get_tag_prefix: returns v when enabled" {
    source_config_parser "with-v-prefix"
    run get_tag_prefix
    assert_equals "v" "$output"
}

@test "get_tag_prefix: returns empty when disabled" {
    source_config_parser "minimal"
    run get_tag_prefix
    assert_empty "$output"
}

# =============================================================================
# COMMIT TYPES
# =============================================================================

@test "get_commit_types_pattern: returns pipe-separated type names" {
    source_config_parser "minimal"
    run get_commit_types_pattern
    # Must contain at least the standard types from defaults.yml
    assert_output_matches "feat"
    assert_output_matches "fix"
    assert_output_matches "chore"
}

@test "get_bump_action: feat returns major" {
    source_config_parser "minimal"
    run get_bump_action "feat"
    assert_equals "major" "$output"
}

@test "get_bump_action: fix returns minor" {
    source_config_parser "minimal"
    run get_bump_action "fix"
    assert_equals "minor" "$output"
}

@test "get_bump_action: unknown type returns none" {
    source_config_parser "minimal"
    run get_bump_action "nonexistent"
    assert_equals "none" "$output"
}

@test "get_types_for_bump: major includes feat" {
    source_config_parser "minimal"
    run get_types_for_bump "major"
    assert_output_matches "feat"
}

@test "get_types_for_bump: minor includes fix" {
    source_config_parser "minimal"
    run get_types_for_bump "minor"
    assert_output_matches "fix"
}

@test "get_commit_type_emoji: feat default emoji is rocket" {
    source_config_parser "minimal"
    run get_commit_type_emoji "feat"
    assert_equals "🚀" "$output"
}

@test "get_commit_type_emoji: fix default emoji is bug" {
    source_config_parser "minimal"
    run get_commit_type_emoji "fix"
    assert_equals "🐛" "$output"
}

# =============================================================================
# CHANGELOG CONFIGURATION
# =============================================================================

@test "get_changelog_file: default is CHANGELOG.md" {
    source_config_parser "minimal"
    run get_changelog_file
    assert_equals "CHANGELOG.md" "$output"
}

@test "get_changelog_title: default is Changelog" {
    source_config_parser "minimal"
    run get_changelog_title
    assert_equals "Changelog" "$output"
}

@test "get_changelog_format: default is minimal" {
    source_config_parser "minimal"
    run get_changelog_format
    assert_equals "minimal" "$output"
}

@test "use_changelog_emojis: true for conventional-full" {
    source_config_parser "conventional-full"
    run use_changelog_emojis
    [ "$status" -eq 0 ]
}

@test "use_changelog_emojis: false for minimal (default)" {
    source_config_parser "minimal"
    run use_changelog_emojis
    [ "$status" -ne 0 ]
}

@test "include_commit_link: true by default" {
    source_config_parser "minimal"
    run include_commit_link
    [ "$status" -eq 0 ]
}

@test "include_ticket_link: true by default" {
    source_config_parser "minimal"
    run include_ticket_link
    [ "$status" -eq 0 ]
}

@test "include_author: true by default" {
    source_config_parser "minimal"
    run include_author
    [ "$status" -eq 0 ]
}

@test "get_commit_url: default is empty" {
    source_config_parser "minimal"
    run get_commit_url
    assert_empty "$output"
}

@test "get_ticket_link_label: default is View ticket" {
    source_config_parser "minimal"
    run get_ticket_link_label
    assert_equals "View ticket" "$output"
}

@test "get_changelog_mode: default is last_commit" {
    source_config_parser "minimal"
    run get_changelog_mode
    assert_equals "last_commit" "$output"
}

@test "get_changelog_mode: conventional-full returns full" {
    source_config_parser "conventional-full"
    run get_changelog_mode
    assert_equals "full" "$output"
}

@test "is_full_changelog_mode: true for conventional-full" {
    source_config_parser "conventional-full"
    run is_full_changelog_mode
    [ "$status" -eq 0 ]
}

@test "is_full_changelog_mode: false for minimal" {
    source_config_parser "minimal"
    run is_full_changelog_mode
    [ "$status" -ne 0 ]
}

# =============================================================================
# PER-FOLDER CHANGELOG
# =============================================================================

@test "is_per_folder_changelog_enabled: true for monorepo" {
    source_config_parser "monorepo"
    run is_per_folder_changelog_enabled
    [ "$status" -eq 0 ]
}

@test "is_per_folder_changelog_enabled: false for minimal" {
    source_config_parser "minimal"
    run is_per_folder_changelog_enabled
    [ "$status" -ne 0 ]
}

@test "get_per_folder_folders: monorepo returns services infrastructure" {
    source_config_parser "monorepo"
    run get_per_folder_folders
    assert_equals "services infrastructure" "$output"
}

@test "get_per_folder_pattern: monorepo returns numbered pattern" {
    source_config_parser "monorepo"
    run get_per_folder_pattern
    assert_equals "^[0-9]{3}-" "$output"
}

@test "get_per_folder_scope_matching: monorepo returns suffix" {
    source_config_parser "monorepo"
    run get_per_folder_scope_matching
    assert_equals "suffix" "$output"
}

@test "get_per_folder_fallback: monorepo returns root" {
    source_config_parser "monorepo"
    run get_per_folder_fallback
    assert_equals "root" "$output"
}

@test "get_per_folder_fallback: default is root" {
    source_config_parser "minimal"
    run get_per_folder_fallback
    assert_equals "root" "$output"
}

# =============================================================================
# VALIDATION
# =============================================================================

@test "require_ticket_prefix: true when required=true and prefixes exist" {
    source_config_parser "ticket-based"
    run require_ticket_prefix
    [ "$status" -eq 0 ]
}

@test "require_ticket_prefix: false for minimal (not required)" {
    source_config_parser "minimal"
    run require_ticket_prefix
    [ "$status" -ne 0 ]
}

@test "require_type_in_last_commit: true by default" {
    source_config_parser "minimal"
    run require_type_in_last_commit
    [ "$status" -eq 0 ]
}

@test "require_type_in_last_commit: true for conventional-full" {
    source_config_parser "conventional-full"
    run require_type_in_last_commit
    [ "$status" -eq 0 ]
}

@test "get_ignore_patterns_regex: default has Merge pattern" {
    source_config_parser "minimal"
    run get_ignore_patterns_regex
    assert_output_matches "Merge"
}

# =============================================================================
# HOTFIX CONFIGURATION
# =============================================================================

@test "get_hotfix_branch_prefix: default is hotfix/" {
    source_config_parser "minimal"
    run get_hotfix_branch_prefix
    assert_equals "hotfix/" "$output"
}

@test "hotfix_validate_commits: true by default" {
    source_config_parser "minimal"
    run hotfix_validate_commits
    [ "$status" -eq 0 ]
}

@test "hotfix_update_changelog_on_main: true by default" {
    source_config_parser "minimal"
    run hotfix_update_changelog_on_main
    [ "$status" -eq 0 ]
}

@test "hotfix_update_changelog_on_preprod: true by default" {
    source_config_parser "minimal"
    run hotfix_update_changelog_on_preprod
    [ "$status" -eq 0 ]
}

@test "get_hotfix_changelog_header: default is HOTFIX" {
    source_config_parser "minimal"
    run get_hotfix_changelog_header
    assert_equals "HOTFIX" "$output"
}

# =============================================================================
# BRANCHES CONFIGURATION
# =============================================================================

@test "get_development_branch: default is development" {
    source_config_parser "minimal"
    run get_development_branch
    assert_equals "development" "$output"
}

@test "get_preprod_branch: default is pre-production" {
    source_config_parser "minimal"
    run get_preprod_branch
    assert_equals "pre-production" "$output"
}

@test "get_production_branch: default is main" {
    source_config_parser "minimal"
    run get_production_branch
    assert_equals "main" "$output"
}

@test "get_tag_branch: default is development" {
    source_config_parser "minimal"
    run get_tag_branch
    assert_equals "development" "$output"
}

@test "get_development_branch: custom-branches returns dev" {
    source_config_parser "custom-branches"
    run get_development_branch
    assert_equals "dev" "$output"
}

@test "get_preprod_branch: custom-branches returns staging" {
    source_config_parser "custom-branches"
    run get_preprod_branch
    assert_equals "staging" "$output"
}

@test "get_production_branch: custom-branches returns master" {
    source_config_parser "custom-branches"
    run get_production_branch
    assert_equals "master" "$output"
}

# =============================================================================
# PATTERN BUILDERS
# =============================================================================

@test "get_enabled_component_count: no-timestamp has 3 (period+major+minor)" {
    source_config_parser "no-timestamp"
    run get_enabled_component_count
    assert_equals "3" "$output"
}

@test "get_enabled_component_count: with-v-prefix has 2 (major+minor)" {
    source_config_parser "with-v-prefix"
    run get_enabled_component_count
    assert_equals "2" "$output"
}

@test "get_tag_pattern: no-timestamp returns 3-part numeric pattern" {
    source_config_parser "no-timestamp"
    run get_tag_pattern
    # period.major.minor — no timestamp, no prefix
    assert_output_matches '^\^'
    assert_output_matches '\$'
    assert_output_matches '\[0-9\]'
}

@test "get_tag_pattern: with-v-prefix includes v prefix" {
    source_config_parser "with-v-prefix"
    run get_tag_pattern
    [[ "$output" == "^v"* ]]
}

@test "get_tag_pattern: with-timestamp includes timestamp group" {
    source_config_parser "with-timestamp"
    run get_tag_pattern
    assert_output_matches '\{12,14\}'
}

@test "build_version_string: all-components builds period.major.minor" {
    source_config_parser "all-components"
    run build_version_string "1" "2" "3"
    assert_equals "1.2.3" "$output"
}

@test "build_version_string: with-v-prefix builds major.minor only" {
    source_config_parser "with-v-prefix"
    run build_version_string "0" "5" "10"
    assert_equals "5.10" "$output"
}

@test "extract_scope_from_commit: returns scope from conventional commit" {
    source_config_parser "conventional-full"
    run extract_scope_from_commit "feat(api): add endpoint"
    assert_equals "api" "$output"
}

@test "extract_scope_from_commit: returns empty for scopeless commit" {
    source_config_parser "conventional-full"
    run extract_scope_from_commit "feat: add feature"
    assert_empty "$output"
}

@test "build_ticket_prefix_pattern: ticket-based returns prefix regex" {
    source_config_parser "ticket-based"
    run build_ticket_prefix_pattern
    assert_output_matches 'AM|TECH'
}

@test "build_ticket_prefix_pattern: conventional returns empty" {
    source_config_parser "conventional-full"
    run build_ticket_prefix_pattern
    assert_empty "$output"
}

@test "build_ticket_full_pattern: conventional returns type pattern" {
    source_config_parser "conventional-full"
    run build_ticket_full_pattern
    assert_output_matches 'feat'
    assert_output_matches 'fix'
}

@test "build_bump_pattern: major bump for conventional includes feat" {
    source_config_parser "conventional-full"
    run build_bump_pattern "major"
    assert_output_matches "feat"
}

@test "get_example_prefix: conventional returns feat(scope)" {
    source_config_parser "conventional-full"
    run get_example_prefix
    assert_equals "feat(scope)" "$output"
}

@test "get_example_prefix: ticket-based returns first prefix (AM)" {
    source_config_parser "ticket-based"
    run get_example_prefix
    assert_equals "AM" "$output"
}

@test "get_example_prefix: minimal with no prefixes returns TICKET" {
    source_config_parser "minimal"
    run get_example_prefix
    assert_equals "TICKET" "$output"
}

# =============================================================================
# VERSION FILE CONFIGURATION
# =============================================================================

@test "is_version_file_enabled: false by default" {
    source_config_parser "minimal"
    run is_version_file_enabled
    [ "$status" -ne 0 ]
}

@test "get_version_file_type: default is yaml" {
    source_config_parser "minimal"
    run get_version_file_type
    assert_equals "yaml" "$output"
}

@test "get_version_file_path: default is version.yaml" {
    source_config_parser "minimal"
    run get_version_file_path
    assert_equals "version.yaml" "$output"
}

@test "get_version_file_key: default is version" {
    source_config_parser "minimal"
    run get_version_file_key
    assert_equals "version" "$output"
}

@test "get_version_file_pattern: default is empty" {
    source_config_parser "minimal"
    run get_version_file_pattern
    assert_empty "$output"
}

@test "get_version_file_replacement: default is empty" {
    source_config_parser "minimal"
    run get_version_file_replacement
    assert_empty "$output"
}

@test "has_version_file_groups: false by default" {
    source_config_parser "minimal"
    run has_version_file_groups
    [ "$status" -ne 0 ]
}

@test "get_version_file_groups_count: 0 by default" {
    source_config_parser "minimal"
    run get_version_file_groups_count
    assert_equals "0" "$output"
}

@test "get_unmatched_files_behavior: default is update_all" {
    source_config_parser "minimal"
    run get_unmatched_files_behavior
    assert_equals "update_all" "$output"
}

# =============================================================================
# config_get and config_get_array (generic)
# =============================================================================

@test "config_get: returns default when key missing" {
    source_config_parser "minimal"
    run config_get "nonexistent.key" "fallback"
    assert_equals "fallback" "$output"
}

@test "config_get: returns value when key exists" {
    source_config_parser "minimal"
    run config_get "commits.format" "conventional"
    assert_equals "ticket" "$output"
}
