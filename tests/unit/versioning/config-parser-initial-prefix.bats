#!/usr/bin/env bats

# config-parser-initial-prefix.bats — unit tests for build_initial_prefix_regex (ticket 055)
#
# Exercises the 4-combination output matrix (epoch.enabled × tag_prefix_v) plus
# edge cases that the regex MUST and MUST NOT match. Uses write_inline_fixture to
# configure each scenario precisely; assertions compare the literal regex output
# AND validate grep behaviour against representative tag strings.

load '../../helpers/setup'
load '../../helpers/assertions'

setup() { common_setup; }
teardown() { common_teardown; }

# =============================================================================
# Output matrix — 4 combinations (epoch.enabled × tag_prefix_v)
# =============================================================================

@test "build_initial_prefix_regex: epoch=on, v-prefix=on → ^v{epoch}\.{major}\." {
    write_inline_fixture "commits:
  format: conventional
version:
  tag_prefix_v: true
  components:
    epoch:
      enabled: true
      initial: 1
    major:
      enabled: true
      initial: 0
    patch:
      enabled: true
      initial: 0
    timestamp:
      enabled: false"

    run build_initial_prefix_regex "1" "0"
    assert_equals '^v1\.0\.' "$output"
}

@test "build_initial_prefix_regex: epoch=on, v-prefix=off → ^{epoch}\.{major}\." {
    write_inline_fixture "commits:
  format: conventional
version:
  tag_prefix_v: false
  components:
    epoch:
      enabled: true
      initial: 1
    major:
      enabled: true
      initial: 0
    patch:
      enabled: true
      initial: 0
    timestamp:
      enabled: false"

    run build_initial_prefix_regex "1" "0"
    assert_equals '^1\.0\.' "$output"
}

@test "build_initial_prefix_regex: epoch=off, v-prefix=on → ^v{major}\." {
    # semver fixture: epoch off, v-prefix on
    source_config_parser "semver"
    run build_initial_prefix_regex "0" "2"
    assert_equals '^v2\.' "$output"
}

@test "build_initial_prefix_regex: epoch=off, v-prefix=off → ^{major}\." {
    write_inline_fixture "commits:
  format: conventional
version:
  tag_prefix_v: false
  components:
    epoch:
      enabled: false
    major:
      enabled: true
      initial: 0
    patch:
      enabled: true
      initial: 0
    timestamp:
      enabled: false"

    run build_initial_prefix_regex "_" "2"
    assert_equals '^2\.' "$output"
}

# =============================================================================
# grep behaviour — regex MUST anchor and use literal dot (v1 vs v10 boundary)
# =============================================================================

@test "build_initial_prefix_regex: v-prefix epoch-off — ^v1\. does NOT match v10.x.y" {
    # Regression guard: trailing \. prevents the v1 → v10 false match.
    # If someone drops the trailing escape under a "simplification", this test fails.
    source_config_parser "semver"
    run build_initial_prefix_regex "0" "1"
    assert_equals '^v1\.' "$output"

    # Validate against real tag strings
    regex='^v1\.'
    echo "v1.0.0" | grep -qE "$regex"
    echo "v1.5.2" | grep -qE "$regex"
    ! echo "v10.0.0" | grep -qE "$regex"
    ! echo "v100.0.0" | grep -qE "$regex"
}

@test "build_initial_prefix_regex: epoch-on v-prefix — ^v1\.0\. does not match v1.10.x" {
    write_inline_fixture "commits:
  format: conventional
version:
  tag_prefix_v: true
  components:
    epoch:
      enabled: true
      initial: 1
    major:
      enabled: true
      initial: 0
    patch:
      enabled: true
      initial: 0
    timestamp:
      enabled: false"

    regex="$(build_initial_prefix_regex "1" "0")"
    assert_equals '^v1\.0\.' "$regex"
    echo "v1.0.0" | grep -qE "$regex"
    echo "v1.0.5" | grep -qE "$regex"
    ! echo "v1.10.0" | grep -qE "$regex"
    ! echo "v2.0.0" | grep -qE "$regex"
}

@test "build_initial_prefix_regex: no v-prefix — ^1\. does NOT match 10.x" {
    write_inline_fixture "commits:
  format: conventional
version:
  tag_prefix_v: false
  components:
    epoch:
      enabled: false
    major:
      enabled: true
      initial: 0
    patch:
      enabled: true
      initial: 0
    timestamp:
      enabled: false"

    regex="$(build_initial_prefix_regex "_" "1")"
    assert_equals '^1\.' "$regex"
    echo "1.0.0" | grep -qE "$regex"
    ! echo "10.0.0" | grep -qE "$regex"
    ! echo "v1.0.0" | grep -qE "$regex"
}
