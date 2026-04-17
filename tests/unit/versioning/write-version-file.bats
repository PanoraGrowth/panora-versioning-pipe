#!/usr/bin/env bats

# write-version-file.bats — tests for the groups-based version file writer
#
# Covers: yaml/json/pattern type inference, tag_prefix_v stripping,
# disabled feature, missing version file error, and glob path expansion.

load '../../helpers/setup'
load '../../helpers/assertions'

LOCKFILE="/tmp/.versioning-merged.lock"

setup() { common_setup; }

teardown() {
    common_teardown
    rm -f /tmp/next_version.txt /tmp/.versioning-merged.yml \
          /tmp/version_files_modified.txt /tmp/bump_type.txt
}

run_write_version_file() {
    local version="$1"
    run flock "$LOCKFILE" sh -c "
        echo '${version}' > /tmp/next_version.txt ; \
        cd '${BATS_TEST_TMPDIR}/repo' && \
        sh '${PIPE_DIR}/versioning/write-version-file.sh' 2>&1
    "
}

read_json_key() {
    local file="$1"
    local key="$2"
    yq -r -p=json ".${key}" "$file"
}

read_yaml_key() {
    local file="$1"
    local key="$2"
    yq -r ".${key}" "$file"
}

# =============================================================================
# YAML type inference
# =============================================================================

@test "yaml: writes plain semver to version.yaml via groups" {
    write_inline_fixture '
commits:
  format: "conventional"
version:
  tag_prefix_v: false
  components:
    major: { enabled: true, initial: 0 }
    patch: { enabled: true, initial: 0 }
version_file:
  enabled: true
  groups:
    - name: "root"
      files:
        - path: "version.yaml"
'
    echo "version: \"0.0.0\"" > "${BATS_TEST_TMPDIR}/repo/version.yaml"

    run_write_version_file "1.2.0"
    [ "$status" -eq 0 ]

    actual=$(read_yaml_key "${BATS_TEST_TMPDIR}/repo/version.yaml" "version")
    assert_equals "1.2.0" "$actual"
}

@test "yaml + tag_prefix_v=true: strips v prefix before writing" {
    write_inline_fixture '
commits:
  format: "conventional"
version:
  tag_prefix_v: true
  components:
    major: { enabled: true, initial: 0 }
    patch: { enabled: true, initial: 0 }
version_file:
  enabled: true
  groups:
    - name: "root"
      files:
        - path: "version.yaml"
'
    echo "version: \"0.0.0\"" > "${BATS_TEST_TMPDIR}/repo/version.yaml"

    run_write_version_file "v0.1.0"
    [ "$status" -eq 0 ]

    actual=$(read_yaml_key "${BATS_TEST_TMPDIR}/repo/version.yaml" "version")
    assert_equals "0.1.0" "$actual"
}

@test "yml extension: inferred as yaml type" {
    write_inline_fixture '
commits:
  format: "conventional"
version:
  tag_prefix_v: false
  components:
    major: { enabled: true, initial: 0 }
    patch: { enabled: true, initial: 0 }
version_file:
  enabled: true
  groups:
    - name: "root"
      files:
        - path: "app.yml"
'
    echo "version: \"0.0.0\"" > "${BATS_TEST_TMPDIR}/repo/app.yml"

    run_write_version_file "2.3.0"
    [ "$status" -eq 0 ]

    actual=$(read_yaml_key "${BATS_TEST_TMPDIR}/repo/app.yml" "version")
    assert_equals "2.3.0" "$actual"
}

# =============================================================================
# JSON type inference
# =============================================================================

@test "json: writes plain semver to package.json via groups" {
    write_inline_fixture '
commits:
  format: "conventional"
version:
  tag_prefix_v: false
  components:
    major: { enabled: true, initial: 0 }
    patch: { enabled: true, initial: 0 }
version_file:
  enabled: true
  groups:
    - name: "root"
      files:
        - path: "package.json"
'
    echo '{"name": "test-pkg", "version": "0.0.0"}' > "${BATS_TEST_TMPDIR}/repo/package.json"

    run_write_version_file "1.0.0"
    [ "$status" -eq 0 ]

    actual=$(read_json_key "${BATS_TEST_TMPDIR}/repo/package.json" "version")
    assert_equals "1.0.0" "$actual"
}

@test "json + tag_prefix_v=true: strips v prefix before writing" {
    write_inline_fixture '
commits:
  format: "conventional"
version:
  tag_prefix_v: true
  components:
    major: { enabled: true, initial: 0 }
    patch: { enabled: true, initial: 0 }
version_file:
  enabled: true
  groups:
    - name: "root"
      files:
        - path: "package.json"
'
    echo '{"name": "test-pkg", "version": "0.0.0"}' > "${BATS_TEST_TMPDIR}/repo/package.json"

    run_write_version_file "v0.1.0"
    [ "$status" -eq 0 ]

    actual=$(read_json_key "${BATS_TEST_TMPDIR}/repo/package.json" "version")
    assert_equals "0.1.0" "$actual"
}

# =============================================================================
# Pattern type inference
# =============================================================================

@test "pattern: replaces placeholder in .ts file" {
    write_inline_fixture '
commits:
  format: "conventional"
version:
  tag_prefix_v: false
  components:
    major: { enabled: true, initial: 0 }
    patch: { enabled: true, initial: 0 }
version_file:
  enabled: true
  groups:
    - name: "root"
      files:
        - path: "src/version.ts"
          pattern: "__VERSION__"
'
    mkdir -p "${BATS_TEST_TMPDIR}/repo/src"
    echo 'export const VERSION = "__VERSION__";' > "${BATS_TEST_TMPDIR}/repo/src/version.ts"

    run_write_version_file "1.0.0"
    [ "$status" -eq 0 ]

    grep -q 'VERSION = "1.0.0"' "${BATS_TEST_TMPDIR}/repo/src/version.ts"
}

@test "pattern + tag_prefix_v=true: does NOT strip v (consumer controls format)" {
    write_inline_fixture '
commits:
  format: "conventional"
version:
  tag_prefix_v: true
  components:
    major: { enabled: true, initial: 0 }
    patch: { enabled: true, initial: 0 }
version_file:
  enabled: true
  groups:
    - name: "root"
      files:
        - path: "src/version.ts"
          pattern: "__VERSION__"
'
    mkdir -p "${BATS_TEST_TMPDIR}/repo/src"
    echo 'export const VERSION = "__VERSION__";' > "${BATS_TEST_TMPDIR}/repo/src/version.ts"

    run_write_version_file "v0.1.0"
    [ "$status" -eq 0 ]

    grep -q 'VERSION = "v0.1.0"' "${BATS_TEST_TMPDIR}/repo/src/version.ts"
}

@test "pattern: missing pattern field → fatal error" {
    write_inline_fixture '
commits:
  format: "conventional"
version:
  tag_prefix_v: false
  components:
    major: { enabled: true, initial: 0 }
    patch: { enabled: true, initial: 0 }
version_file:
  enabled: true
  groups:
    - name: "root"
      files:
        - path: "src/version.ts"
'
    mkdir -p "${BATS_TEST_TMPDIR}/repo/src"
    echo 'export const VERSION = "__VERSION__";' > "${BATS_TEST_TMPDIR}/repo/src/version.ts"

    run_write_version_file "1.0.0"
    [ "$status" -ne 0 ]
}

# =============================================================================
# Multiple files in one group
# =============================================================================

@test "multiple files in group: all updated" {
    write_inline_fixture '
commits:
  format: "conventional"
version:
  tag_prefix_v: false
  components:
    major: { enabled: true, initial: 0 }
    patch: { enabled: true, initial: 0 }
version_file:
  enabled: true
  groups:
    - name: "root"
      files:
        - path: "version.yaml"
        - path: "package.json"
'
    echo "version: \"0.0.0\"" > "${BATS_TEST_TMPDIR}/repo/version.yaml"
    echo '{"version": "0.0.0"}' > "${BATS_TEST_TMPDIR}/repo/package.json"

    run_write_version_file "1.1.0"
    [ "$status" -eq 0 ]

    actual_yaml=$(read_yaml_key "${BATS_TEST_TMPDIR}/repo/version.yaml" "version")
    actual_json=$(read_json_key "${BATS_TEST_TMPDIR}/repo/package.json" "version")
    assert_equals "1.1.0" "$actual_yaml"
    assert_equals "1.1.0" "$actual_json"
}

# =============================================================================
# Feature-disabled and error paths
# =============================================================================

@test "version_file disabled: exits 0, files untouched" {
    write_inline_fixture '
commits:
  format: "conventional"
version:
  tag_prefix_v: false
  components:
    major: { enabled: true, initial: 0 }
    patch: { enabled: true, initial: 0 }
version_file:
  enabled: false
  groups:
    - name: "root"
      files:
        - path: "version.yaml"
'
    echo "version: \"0.0.0\"" > "${BATS_TEST_TMPDIR}/repo/version.yaml"

    run_write_version_file "1.0.0"
    [ "$status" -eq 0 ]

    actual=$(read_yaml_key "${BATS_TEST_TMPDIR}/repo/version.yaml" "version")
    assert_equals "0.0.0" "$actual"
}

@test "no groups configured: exits 0 with warning" {
    write_inline_fixture '
commits:
  format: "conventional"
version:
  tag_prefix_v: false
  components:
    major: { enabled: true, initial: 0 }
    patch: { enabled: true, initial: 0 }
version_file:
  enabled: true
  groups: []
'
    run_write_version_file "1.0.0"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No groups configured"* ]]
}

@test "missing /tmp/next_version.txt: exits non-zero" {
    write_inline_fixture '
commits:
  format: "conventional"
version:
  tag_prefix_v: false
  components:
    major: { enabled: true, initial: 0 }
    patch: { enabled: true, initial: 0 }
version_file:
  enabled: true
  groups:
    - name: "root"
      files:
        - path: "version.yaml"
'
    run flock "$LOCKFILE" sh -c "
        rm -f /tmp/next_version.txt ; \
        cd '${BATS_TEST_TMPDIR}/repo' && \
        sh '${PIPE_DIR}/versioning/write-version-file.sh' 2>&1
    "
    [ "$status" -ne 0 ]
}

@test "path glob no match: logs warning and continues (exit 0)" {
    # Use an actual glob (with *) that matches nothing — post-#94, paths
    # WITHOUT glob chars now auto-create the file, so testing "no match"
    # requires a pattern containing * or ? that actually expands to nothing.
    write_inline_fixture '
commits:
  format: "conventional"
version:
  tag_prefix_v: false
  components:
    major: { enabled: true, initial: 0 }
    patch: { enabled: true, initial: 0 }
version_file:
  enabled: true
  groups:
    - name: "root"
      files:
        - path: "nonexistent/*.yaml"
'
    run_write_version_file "1.0.0"
    [ "$status" -eq 0 ]
    [[ "$output" == *"no files matched"* ]]
}
