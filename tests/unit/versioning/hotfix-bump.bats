#!/usr/bin/env bats

# hotfix-bump.bats — tests for the hotfix routing in calculate-version.sh
#
# Exercises the scenario-driven PATCH bump end-to-end: seeds a tag, makes a
# commit, writes /tmp/scenario.env, runs calculate-version.sh as a subprocess
# under flock, and captures BUMP_TYPE + NEXT_VERSION from the state files
# inside the same locked shell so parallel jobs can't race.

load '../../helpers/setup'
load '../../helpers/assertions'

LOCKFILE="/tmp/.versioning-merged.lock"

setup() { common_setup; }

teardown() {
    common_teardown
    rm -f /tmp/scenario.env /tmp/.versioning-merged.yml \
          /tmp/next_version.txt /tmp/bump_type.txt /tmp/latest_tag.txt
}

# Seed repo with fixture + initial tag + new commit, then run calculate-version.
# Captures the result state files into BATS_TEST_TMPDIR so the assertions can
# read them after the flock releases.
#
# Usage: run_calculate "<fixture>" "<scenario>" "<initial_tag>" "<new_commit_msg>"
run_calculate() {
    local fixture="$1"
    local scenario="$2"
    local initial_tag="$3"
    local commit_msg="$4"

    cp "${PIPE_DIR}/tests/fixtures/${fixture}.yml" \
       "${BATS_TEST_TMPDIR}/repo/.versioning.yml"

    cd "${BATS_TEST_TMPDIR}/repo" || return 1

    # Tag the init commit as the initial baseline
    if [ -n "$initial_tag" ]; then
        git tag "$initial_tag"
    fi

    # New commit to bump against
    echo "artifact" > artifact.txt
    git add artifact.txt .versioning.yml >/dev/null
    git commit -q -m "$commit_msg"

    echo "SCENARIO=${scenario}" > /tmp/scenario.env

    # Capture state files INSIDE the lock so parallel jobs cannot overwrite
    # them between the script finishing and our cat.
    run flock "$LOCKFILE" sh -c "
        cd '${BATS_TEST_TMPDIR}/repo' && \
        sh '${PIPE_DIR}/versioning/calculate-version.sh' >/dev/null 2>&1 ; \
        echo BUMP_TYPE=\$(cat /tmp/bump_type.txt 2>/dev/null) ; \
        echo NEXT_VERSION=\$(cat /tmp/next_version.txt 2>/dev/null)
    "
}

# =============================================================================
# Hotfix scenarios with patch enabled
# =============================================================================

@test "hotfix_to_main + patch enabled: bumps patch 0 → 1" {
    run_calculate "with-patch" "hotfix_to_main" "v0.5.9" "hotfix: patch auth"
    [ "$status" -eq 0 ]
    assert_output_matches 'BUMP_TYPE=patch'
    assert_output_matches 'NEXT_VERSION=v0\.5\.9\.1'
}

@test "hotfix_to_main + patch enabled: bumps patch 1 → 2" {
    run_calculate "with-patch" "hotfix_to_main" "v0.5.9.1" "hotfix: second patch"
    [ "$status" -eq 0 ]
    assert_output_matches 'BUMP_TYPE=patch'
    assert_output_matches 'NEXT_VERSION=v0\.5\.9\.2'
}

@test "hotfix_to_main + patch disabled: falls back to minor bump (backward compat)" {
    # minimal fixture has patch disabled. Hotfix commit still bumps per commit
    # type convention (fix → minor), preserving the pre-wire-up behaviour for
    # consumers that never opt in.
    run_calculate "minimal" "hotfix_to_main" "" "fix: something"
    [ "$status" -eq 0 ]
    assert_output_matches 'BUMP_TYPE=minor'
}

# =============================================================================
# Development release with patch enabled — reset semantics
# =============================================================================

@test "development_release + major bump: resets patch to 0" {
    run_calculate "with-patch" "development_release" "v0.5.9.3" "feat: new thing"
    [ "$status" -eq 0 ]
    assert_output_matches 'BUMP_TYPE=major'
    # After major bump, version becomes 0.6.0 (patch dropped because = 0)
    assert_output_matches 'NEXT_VERSION=v0\.6\.0$'
}

@test "development_release + minor bump: resets patch to 0" {
    run_calculate "with-patch" "development_release" "v0.5.9.2" "fix: routine fix"
    [ "$status" -eq 0 ]
    assert_output_matches 'BUMP_TYPE=minor'
    # After minor bump, patch=0 so tag is v0.5.10 (patch omitted)
    assert_output_matches 'NEXT_VERSION=v0\.5\.10$'
}

@test "hotfix_to_preprod + patch enabled: bumps patch (same routing as _main)" {
    run_calculate "with-patch" "hotfix_to_preprod" "v0.5.9" "hotfix: preprod patch"
    [ "$status" -eq 0 ]
    assert_output_matches 'BUMP_TYPE=patch'
    assert_output_matches 'NEXT_VERSION=v0\.5\.9\.1'
}

@test "bump_type.txt contains 'patch' after hotfix bump" {
    run_calculate "with-patch" "hotfix_to_main" "v0.5.9" "hotfix: check bump type file"
    [ "$status" -eq 0 ]
    # Explicit grep on the captured BUMP_TYPE line — anchored, no partial matches
    echo "$output" | grep -q '^BUMP_TYPE=patch$'
}
