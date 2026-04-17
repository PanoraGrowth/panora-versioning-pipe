#!/usr/bin/env bats

# tag-building-extended.bats — additional tag building coverage
#
# Covers: separators.tag_append with non-empty value, timestamp.format with
# alternative format, timestamp.timezone with non-UTC zone.

load '../../helpers/setup'
load '../../helpers/assertions'

LOCKFILE="/tmp/.versioning-merged.lock"

setup() { common_setup; }

teardown() {
    common_teardown
    rm -f /tmp/scenario.env /tmp/.versioning-merged.yml \
          /tmp/next_version.txt /tmp/bump_type.txt /tmp/latest_tag.txt
}

run_calculate() {
    local scenario="$2"
    local initial_tag="$3"
    local commit_msg="$4"

    cp "${PIPE_DIR}/tests/fixtures/${1}.yml" \
       "${BATS_TEST_TMPDIR}/repo/.versioning.yml"

    cd "${BATS_TEST_TMPDIR}/repo" || return 1

    if [ -n "$initial_tag" ]; then
        git tag "$initial_tag"
    fi

    echo "artifact" > artifact.txt
    git add artifact.txt .versioning.yml >/dev/null
    git commit -q -m "$commit_msg"

    run flock "$LOCKFILE" sh -c "
        echo 'SCENARIO=${scenario}' > /tmp/scenario.env ; \
        cd '${BATS_TEST_TMPDIR}/repo' && \
        sh '${PIPE_DIR}/versioning/calculate-version.sh' >/dev/null 2>&1 ; \
        echo BUMP_TYPE=\$(cat /tmp/bump_type.txt 2>/dev/null) ; \
        echo NEXT_VERSION=\$(cat /tmp/next_version.txt 2>/dev/null)
    "
}

run_calculate_inline() {
    local fixture_content="$1"
    local scenario="$2"
    local initial_tag="$3"
    local commit_msg="$4"

    printf '%s\n' "$fixture_content" > "${BATS_TEST_TMPDIR}/repo/.versioning.yml"

    cd "${BATS_TEST_TMPDIR}/repo" || return 1

    if [ -n "$initial_tag" ]; then
        git tag "$initial_tag"
    fi

    echo "artifact" > artifact.txt
    git add artifact.txt .versioning.yml >/dev/null
    git commit -q -m "$commit_msg"

    run flock "$LOCKFILE" sh -c "
        echo 'SCENARIO=${scenario}' > /tmp/scenario.env ; \
        cd '${BATS_TEST_TMPDIR}/repo' && \
        sh '${PIPE_DIR}/versioning/calculate-version.sh' >/dev/null 2>&1 ; \
        echo NEXT_VERSION=\$(cat /tmp/next_version.txt 2>/dev/null)
    "
}

# =============================================================================
# separators.tag_append — non-empty value
# =============================================================================

@test "tag_append: non-empty value (-rc1) is appended to the end of the tag" {
    # Ticket 055: major.initial must match seed tag's major — namespace filter is ^v{major.initial}\.
    run_calculate_inline '
commits:
  format: "conventional"
version:
  tag_prefix_v: true
  components:
    epoch:
      enabled: false
    major:
      enabled: true
      initial: 1
    patch:
      enabled: true
      initial: 0
    timestamp:
      enabled: false
  separators:
    version: "."
    timestamp: "."
    tag_append: "-rc1"
' "development_release" "v1.0" "feat: release candidate"

    [ "$status" -eq 0 ]
    assert_output_matches 'NEXT_VERSION=v1\.1-rc1$'
}

@test "tag_append: empty value (default) — tag has no suffix" {
    # Ticket 055: major.initial must match seed tag's major.
    run_calculate_inline '
commits:
  format: "conventional"
version:
  tag_prefix_v: true
  components:
    epoch:
      enabled: false
    major:
      enabled: true
      initial: 1
    patch:
      enabled: true
      initial: 0
    timestamp:
      enabled: false
  separators:
    version: "."
    timestamp: "."
    tag_append: ""
' "development_release" "v1.0" "feat: no suffix"

    [ "$status" -eq 0 ]
    assert_output_matches 'NEXT_VERSION=v1\.1$'
}

# =============================================================================
# timestamp.format — alternative format
# =============================================================================

@test "timestamp.format: alternative format (%Y-%m-%d) is applied in tag" {
    run_calculate_inline '
commits:
  format: "conventional"
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
      enabled: true
      format: "%Y-%m-%d"
      timezone: "UTC"
  separators:
    version: "."
    timestamp: "."
    tag_append: ""
' "development_release" "" "feat: custom ts format"

    [ "$status" -eq 0 ]
    # Tag should end with a date in YYYY-MM-DD format (feat bumps patch from 0 to 1)
    assert_output_matches 'NEXT_VERSION=0\.1\.[0-9]{4}-[0-9]{2}-[0-9]{2}$'
}

@test "timestamp.format: default format (%Y%m%d%H%M%S) produces 14-digit timestamp" {
    # with-timestamp has epoch.enabled=true → tag is epoch.major.patch.TIMESTAMP
    run_calculate "with-timestamp" "development_release" "" "feat: default ts format"
    [ "$status" -eq 0 ]
    assert_output_matches 'NEXT_VERSION=0\.0\.[0-9]+\.[0-9]{14}$'
}

# =============================================================================
# timestamp.timezone — non-UTC zone
# =============================================================================

@test "timestamp.timezone: America/Buenos_Aires — timestamp is generated (non-UTC zone)" {
    run_calculate_inline '
commits:
  format: "conventional"
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
      enabled: true
      format: "%Y%m%d%H%M%S"
      timezone: "America/Buenos_Aires"
  separators:
    version: "."
    timestamp: "."
    tag_append: ""
' "development_release" "" "feat: bsas timezone"

    [ "$status" -eq 0 ]
    # Tag format: major.patch.YYYYMMDDHHMMSS — feat bump moves patch from 0 to 1
    assert_output_matches 'NEXT_VERSION=0\.1\.[0-9]{14}$'
}

@test "timestamp.timezone: Europe/Madrid — timestamp is generated (non-UTC zone)" {
    run_calculate_inline '
commits:
  format: "conventional"
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
      enabled: true
      format: "%Y%m%d%H%M%S"
      timezone: "Europe/Madrid"
  separators:
    version: "."
    timestamp: "."
    tag_append: ""
' "development_release" "" "feat: madrid timezone"

    [ "$status" -eq 0 ]
    assert_output_matches 'NEXT_VERSION=0\.1\.[0-9]{14}$'
}
