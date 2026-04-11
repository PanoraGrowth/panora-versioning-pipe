#!/usr/bin/env bats

# write-version-file.bats — regression tests for issue #47
#
# When `version.tag_prefix_v: true` + `version_file.type: json|yaml`, the
# pipe must write PLAIN semver (no `v` prefix) into the target file.
# `regex` mode is unaffected — consumers template `{{VERSION}}` in their
# replacement and keep control of the prefix themselves.
#
# Mirrors the `hotfix-bump.bats` pattern: each test writes an inline
# fixture, creates the target file + /tmp/next_version.txt, runs the
# script under flock, and asserts the resulting file content.

load '../../helpers/setup'
load '../../helpers/assertions'

LOCKFILE="/tmp/.versioning-merged.lock"

setup() { common_setup; }

teardown() {
    common_teardown
    rm -f /tmp/next_version.txt /tmp/.versioning-merged.yml \
          /tmp/version_files_modified.txt /tmp/bump_type.txt
}

# Run write-version-file.sh under flock, cd'ing into the test repo.
# Usage: run_write_version_file
run_write_version_file() {
    run flock "$LOCKFILE" sh -c "
        cd '${BATS_TEST_TMPDIR}/repo' && \
        sh '${PIPE_DIR}/versioning/write-version-file.sh' 2>&1
    "
}

# Read a key from a JSON file via yq.
read_json_key() {
    local file="$1"
    local key="$2"
    yq -r -p=json ".${key}" "$file"
}

# Read a key from a YAML file via yq.
read_yaml_key() {
    local file="$1"
    local key="$2"
    yq -r ".${key}" "$file"
}

# =============================================================================
# JSON mode
# =============================================================================

@test "json + tag_prefix_v=true: writes plain semver (no v prefix)" {
    write_inline_fixture '
commits:
  format: "conventional"
version:
  tag_prefix_v: true
  components:
    major: { enabled: true, initial: 0 }
    minor: { enabled: true, initial: 0 }
version_file:
  enabled: true
  type: "json"
  file: "package.json"
  key: "version"
'
    echo '{"name": "test-pkg", "version": "0.0.0"}' > "${BATS_TEST_TMPDIR}/repo/package.json"
    echo "v0.1.0" > /tmp/next_version.txt

    run_write_version_file
    [ "$status" -eq 0 ]

    actual=$(read_json_key "${BATS_TEST_TMPDIR}/repo/package.json" "version")
    assert_equals "0.1.0" "$actual"
}

@test "json + tag_prefix_v=true + patch component: writes plain semver with dot" {
    write_inline_fixture '
commits:
  format: "conventional"
version:
  tag_prefix_v: true
  components:
    major: { enabled: true, initial: 0 }
    minor: { enabled: true, initial: 0 }
    patch: { enabled: true, initial: 0 }
version_file:
  enabled: true
  type: "json"
  file: "package.json"
  key: "version"
'
    echo '{"name": "test-pkg", "version": "0.0.0"}' > "${BATS_TEST_TMPDIR}/repo/package.json"
    echo "v0.1.0.1" > /tmp/next_version.txt

    run_write_version_file
    [ "$status" -eq 0 ]

    actual=$(read_json_key "${BATS_TEST_TMPDIR}/repo/package.json" "version")
    assert_equals "0.1.0.1" "$actual"
}

@test "json + tag_prefix_v=false: writes value unchanged (no strip)" {
    write_inline_fixture '
commits:
  format: "conventional"
version:
  tag_prefix_v: false
  components:
    major: { enabled: true, initial: 0 }
    minor: { enabled: true, initial: 0 }
version_file:
  enabled: true
  type: "json"
  file: "package.json"
  key: "version"
'
    echo '{"name": "test-pkg", "version": "0.0.0"}' > "${BATS_TEST_TMPDIR}/repo/package.json"
    echo "0.1.0" > /tmp/next_version.txt

    run_write_version_file
    [ "$status" -eq 0 ]

    actual=$(read_json_key "${BATS_TEST_TMPDIR}/repo/package.json" "version")
    assert_equals "0.1.0" "$actual"
}

@test "json + nested key: strips prefix and writes at nested path" {
    write_inline_fixture '
commits:
  format: "conventional"
version:
  tag_prefix_v: true
  components:
    major: { enabled: true, initial: 0 }
    minor: { enabled: true, initial: 0 }
version_file:
  enabled: true
  type: "json"
  file: "pkg.json"
  key: "metadata.version"
'
    echo '{"metadata": {"version": "0.0.0"}}' > "${BATS_TEST_TMPDIR}/repo/pkg.json"
    echo "v2.3.0" > /tmp/next_version.txt

    run_write_version_file
    [ "$status" -eq 0 ]

    actual=$(read_json_key "${BATS_TEST_TMPDIR}/repo/pkg.json" "metadata.version")
    assert_equals "2.3.0" "$actual"
}

# =============================================================================
# YAML mode
# =============================================================================

@test "yaml + tag_prefix_v=true: writes plain semver (no v prefix)" {
    write_inline_fixture '
commits:
  format: "conventional"
version:
  tag_prefix_v: true
  components:
    major: { enabled: true, initial: 0 }
    minor: { enabled: true, initial: 0 }
version_file:
  enabled: true
  type: "yaml"
  file: "version.yaml"
  key: "version"
'
    echo "version: \"0.0.0\"" > "${BATS_TEST_TMPDIR}/repo/version.yaml"
    echo "v0.1.0" > /tmp/next_version.txt

    run_write_version_file
    [ "$status" -eq 0 ]

    actual=$(read_yaml_key "${BATS_TEST_TMPDIR}/repo/version.yaml" "version")
    assert_equals "0.1.0" "$actual"
}

@test "yaml + tag_prefix_v=false: writes value unchanged" {
    write_inline_fixture '
commits:
  format: "conventional"
version:
  tag_prefix_v: false
  components:
    major: { enabled: true, initial: 0 }
    minor: { enabled: true, initial: 0 }
version_file:
  enabled: true
  type: "yaml"
  file: "version.yaml"
  key: "version"
'
    echo "version: \"0.0.0\"" > "${BATS_TEST_TMPDIR}/repo/version.yaml"
    echo "0.1.0" > /tmp/next_version.txt

    run_write_version_file
    [ "$status" -eq 0 ]

    actual=$(read_yaml_key "${BATS_TEST_TMPDIR}/repo/version.yaml" "version")
    assert_equals "0.1.0" "$actual"
}

# =============================================================================
# Regex mode — consumer controls the prefix, script MUST NOT strip
# =============================================================================

@test "regex + tag_prefix_v=true + {{VERSION}}: keeps the v prefix (consumer opted in)" {
    write_inline_fixture '
commits:
  format: "conventional"
version:
  tag_prefix_v: true
  components:
    major: { enabled: true, initial: 0 }
    minor: { enabled: true, initial: 0 }
version_file:
  enabled: true
  type: "regex"
  pattern: "__VERSION__"
  replacement: "{{VERSION}}"
  files:
    - "src/version.ts"
'
    mkdir -p "${BATS_TEST_TMPDIR}/repo/src"
    echo 'export const VERSION = "__VERSION__";' > "${BATS_TEST_TMPDIR}/repo/src/version.ts"
    echo "v0.1.0" > /tmp/next_version.txt

    run_write_version_file
    [ "$status" -eq 0 ]

    grep -q 'VERSION = "v0.1.0"' "${BATS_TEST_TMPDIR}/repo/src/version.ts"
}

# =============================================================================
# Feature-disabled and error paths
# =============================================================================

@test "version_file disabled: script exits 0 and does not touch files" {
    write_inline_fixture '
commits:
  format: "conventional"
version:
  tag_prefix_v: true
  components:
    major: { enabled: true, initial: 0 }
    minor: { enabled: true, initial: 0 }
version_file:
  enabled: false
  type: "json"
  file: "package.json"
  key: "version"
'
    echo '{"version": "0.0.0"}' > "${BATS_TEST_TMPDIR}/repo/package.json"
    echo "v0.1.0" > /tmp/next_version.txt

    run_write_version_file
    [ "$status" -eq 0 ]

    # File must remain untouched
    actual=$(read_json_key "${BATS_TEST_TMPDIR}/repo/package.json" "version")
    assert_equals "0.0.0" "$actual"
}

@test "missing /tmp/next_version.txt: script exits non-zero" {
    write_inline_fixture '
commits:
  format: "conventional"
version:
  tag_prefix_v: true
  components:
    major: { enabled: true, initial: 0 }
    minor: { enabled: true, initial: 0 }
version_file:
  enabled: true
  type: "json"
  file: "package.json"
  key: "version"
'
    echo '{"version": "0.0.0"}' > "${BATS_TEST_TMPDIR}/repo/package.json"
    rm -f /tmp/next_version.txt

    run_write_version_file
    [ "$status" -ne 0 ]
}
