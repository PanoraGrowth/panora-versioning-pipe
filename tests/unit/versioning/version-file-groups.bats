#!/usr/bin/env bats

# version-file-groups.bats — tests for matches_glob, should_update_group,
# infer_write_type, and config-parser group helpers.

load '../../helpers/setup'
load '../../helpers/assertions'

LOCKFILE="/tmp/.versioning-merged.lock"
PIPE_DIR="/pipe"

setup() {
    common_setup
    # Extract matches_glob and infer_write_type from write-version-file.sh.
    # The script has set -e and top-level side effects, so we extract functions
    # individually and eval them.
    eval "$(sed -n '/^matches_glob()/,/^}/p' "${PIPE_DIR}/versioning/write-version-file.sh")"
    eval "$(sed -n '/^infer_write_type()/,/^}/p' "${PIPE_DIR}/versioning/write-version-file.sh")"
}

teardown() {
    common_teardown
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

# =============================================================================
# infer_write_type
# =============================================================================

@test "infer_write_type: .yaml → yaml" {
    run infer_write_type "version.yaml"
    assert_equals "yaml" "$output"
}

@test "infer_write_type: .yml → yaml" {
    run infer_write_type "app.yml"
    assert_equals "yaml" "$output"
}

@test "infer_write_type: .json → json" {
    run infer_write_type "package.json"
    assert_equals "json" "$output"
}

@test "infer_write_type: .ts → pattern" {
    run infer_write_type "src/version.ts"
    assert_equals "pattern" "$output"
}

@test "infer_write_type: .txt → pattern" {
    run infer_write_type "VERSION.txt"
    assert_equals "pattern" "$output"
}

@test "infer_write_type: no extension → pattern" {
    run infer_write_type "VERSION"
    assert_equals "pattern" "$output"
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
  groups:
    - name: "app"
      trigger_paths: ["src/**"]
      files:
        - path: "src/version.ts"
          pattern: "__VERSION__"
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
  groups:
    - name: "frontend"
      trigger_paths: ["packages/frontend/**"]
      files:
        - path: "packages/frontend/version.yaml"
    - name: "backend"
      trigger_paths: ["packages/backend/**"]
      files:
        - path: "packages/backend/version.yaml"
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
  groups:
    - name: "frontend"
      trigger_paths:
        - "packages/frontend/**"
        - "packages/frontend/*"
      files:
        - path: "packages/frontend/version.yaml"
'
    run get_version_file_group_trigger_paths 0
    [[ "$output" == *"packages/frontend/**"* ]]
    [[ "$output" == *"packages/frontend/*"* ]]
}

@test "get_version_file_group_trigger_paths: empty when not set (always-update group)" {
    write_inline_fixture '
commits:
  format: "conventional"
version_file:
  enabled: true
  groups:
    - name: "root"
      files:
        - path: "version.yaml"
'
    run get_version_file_group_trigger_paths 0
    assert_empty "$output"
}

@test "get_version_file_group_name: defaults to group_N when name absent" {
    write_inline_fixture '
commits:
  format: "conventional"
version_file:
  enabled: true
  groups:
    - files:
        - path: "version.yaml"
'
    run get_version_file_group_name 0
    assert_equals "group_0" "$output"
}
