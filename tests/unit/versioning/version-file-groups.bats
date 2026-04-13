#!/usr/bin/env bats

# Tests for matches_glob() and version-file group matching logic.
#
# matches_glob converts a glob pattern to a regex and checks file paths.
# The groups flow uses trigger_paths + matches_glob to decide which version
# files to update in monorepo setups.
#
# Sourcing write-version-file.sh directly is not feasible (it has side effects
# and calls exit). Instead we source the function definition in isolation.

load '../../helpers/setup'
load '../../helpers/assertions'

LOCKFILE="/tmp/.versioning-merged.lock"
PIPE_DIR="/pipe"

setup() {
    common_setup
    # Source matches_glob by extracting just the function from write-version-file.sh.
    # The script has set -e and top-level side effects, so we extract the function
    # body using sed and eval it.
    eval "$(sed -n '/^matches_glob()/,/^}/p' "${PIPE_DIR}/versioning/write-version-file.sh")"
}

teardown() {
    common_teardown
    rm -f /tmp/group_matched /tmp/file_matched /tmp/unmatched_files
}

# =============================================================================
# matches_glob — basic patterns
# =============================================================================

@test "matches_glob: exact file match" {
    run matches_glob "src/main.ts" "src/main.ts"
    [ "$status" -eq 0 ]
}

@test "matches_glob: exact file — no match" {
    run matches_glob "src/main.ts" "src/other.ts"
    [ "$status" -ne 0 ]
}

@test "matches_glob: single wildcard * matches filename" {
    run matches_glob "src/main.ts" "src/*.ts"
    [ "$status" -eq 0 ]
}

@test "matches_glob: single wildcard * does not cross directories" {
    run matches_glob "src/deep/main.ts" "src/*.ts"
    [ "$status" -ne 0 ]
}

# =============================================================================
# matches_glob — doublestar **
# =============================================================================

@test "matches_glob: ** matches nested path" {
    run matches_glob "packages/frontend/src/app/main.ts" "packages/frontend/**"
    [ "$status" -eq 0 ]
}

@test "matches_glob: ** matches single level" {
    run matches_glob "packages/frontend/file.ts" "packages/frontend/**"
    [ "$status" -eq 0 ]
}

@test "matches_glob: ** at start matches any prefix" {
    run matches_glob "deep/nested/file.js" "**/*.js"
    [ "$status" -eq 0 ]
}

@test "matches_glob: ** does not match different base path" {
    run matches_glob "packages/backend/src/main.ts" "packages/frontend/**"
    [ "$status" -ne 0 ]
}

# =============================================================================
# matches_glob — edge cases
# =============================================================================

@test "matches_glob: dot in filename is matched literally" {
    run matches_glob "package.json" "package.json"
    [ "$status" -eq 0 ]
}

@test "matches_glob: dot in pattern does not match arbitrary char" {
    run matches_glob "packageXjson" "package.json"
    [ "$status" -ne 0 ]
}

@test "matches_glob: empty pattern — no match" {
    run matches_glob "src/file.ts" ""
    [ "$status" -ne 0 ]
}

@test "matches_glob: pattern with single * at end" {
    run matches_glob "packages/frontend/README.md" "packages/frontend/*"
    [ "$status" -eq 0 ]
}

@test "matches_glob: * matches trailing slash (zero-width)" {
    # The regex [^\/]* matches zero or more non-slash chars,
    # so "packages/frontend/" matches "packages/frontend/*"
    run matches_glob "packages/frontend/" "packages/frontend/*"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Config-parser group helpers (via fixtures)
# =============================================================================

@test "has_version_file_groups: returns true when groups are configured" {
    write_inline_fixture '
commits:
  format: "conventional"
version_file:
  enabled: true
  type: "regex"
  groups:
    - name: "app"
      trigger_paths: ["src/**"]
      files: ["src/version.ts"]
'
    run has_version_file_groups
    [ "$status" -eq 0 ]
}

@test "has_version_file_groups: returns false when groups is empty" {
    write_inline_fixture '
commits:
  format: "conventional"
version_file:
  enabled: true
  type: "regex"
  groups: []
'
    run has_version_file_groups
    [ "$status" -ne 0 ]
}

@test "get_version_file_groups_count: returns correct count" {
    write_inline_fixture '
commits:
  format: "conventional"
version_file:
  enabled: true
  type: "regex"
  groups:
    - name: "frontend"
      trigger_paths: ["packages/frontend/**"]
      files: ["packages/frontend/version.ts"]
    - name: "backend"
      trigger_paths: ["packages/backend/**"]
      files: ["packages/backend/version.txt"]
'
    run get_version_file_groups_count
    assert_equals "2" "$output"
}

@test "get_version_file_group_trigger_paths: returns paths for group index" {
    write_inline_fixture '
commits:
  format: "conventional"
version_file:
  enabled: true
  type: "regex"
  groups:
    - name: "frontend"
      trigger_paths:
        - "packages/frontend/**"
        - "packages/frontend/*"
      files: ["packages/frontend/version.ts"]
'
    run get_version_file_group_trigger_paths 0
    [[ "$output" == *"packages/frontend/**"* ]]
    [[ "$output" == *"packages/frontend/*"* ]]
}

@test "get_unmatched_files_behavior: defaults to update_all" {
    write_inline_fixture '
commits:
  format: "conventional"
version_file:
  enabled: true
  type: "regex"
  groups: []
'
    run get_unmatched_files_behavior
    assert_equals "update_all" "$output"
}

@test "get_unmatched_files_behavior: returns configured value — skip maps to update_none" {
    write_inline_fixture '
commits:
  format: "conventional"
version_file:
  enabled: true
  type: "regex"
  groups: []
  unmatched_files_behavior: "update_none"
'
    run get_unmatched_files_behavior
    assert_equals "update_none" "$output"
}

@test "get_unmatched_files_behavior: returns error when configured" {
    write_inline_fixture '
commits:
  format: "conventional"
version_file:
  enabled: true
  type: "regex"
  groups: []
  unmatched_files_behavior: "error"
'
    run get_unmatched_files_behavior
    assert_equals "error" "$output"
}

@test "is_version_file_group_update_all: true when set" {
    write_inline_fixture '
commits:
  format: "conventional"
version_file:
  enabled: true
  type: "regex"
  groups:
    - name: "shared"
      trigger_paths: ["packages/shared/**"]
      files: ["packages/shared/version.txt"]
      update_all: true
'
    run is_version_file_group_update_all 0
    [ "$status" -eq 0 ]
}

@test "is_version_file_group_update_all: false by default" {
    write_inline_fixture '
commits:
  format: "conventional"
version_file:
  enabled: true
  type: "regex"
  groups:
    - name: "app"
      trigger_paths: ["src/**"]
      files: ["src/version.ts"]
'
    run is_version_file_group_update_all 0
    [ "$status" -ne 0 ]
}
