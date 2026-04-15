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

    # Capture state files INSIDE the lock so parallel jobs cannot overwrite
    # them between the script finishing and our cat.
    run flock "$LOCKFILE" sh -c "
        echo 'SCENARIO=${scenario}' > /tmp/scenario.env ; \
        cd '${BATS_TEST_TMPDIR}/repo' && \
        sh '${PIPE_DIR}/versioning/calculate-version.sh' >/dev/null 2>&1 ; \
        echo BUMP_TYPE=\$(cat /tmp/bump_type.txt 2>/dev/null) ; \
        echo NEXT_VERSION=\$(cat /tmp/next_version.txt 2>/dev/null)
    "
}

# =============================================================================
# Hotfix scenarios with patch enabled
# =============================================================================

@test "hotfix scenario + patch enabled: bumps patch 0 → 1" {
    run_calculate "with-patch" "hotfix" "v0.5.9" "hotfix: patch auth"
    [ "$status" -eq 0 ]
    assert_output_matches 'BUMP_TYPE=patch'
    assert_output_matches 'NEXT_VERSION=v0\.5\.9\.1'
}

@test "hotfix scenario + patch enabled: bumps patch 1 → 2" {
    run_calculate "with-patch" "hotfix" "v0.5.9.1" "hotfix: second patch"
    [ "$status" -eq 0 ]
    assert_output_matches 'BUMP_TYPE=patch'
    assert_output_matches 'NEXT_VERSION=v0\.5\.9\.2'
}

@test "hotfix scenario + patch disabled: no-op (empty next_version, INFO log)" {
    # patch-disabled fixture has patch.enabled: false explicitly. With the v0.6.3
    # design, hotfix + patch disabled is a deliberate no-op — the script exits
    # early with an INFO log and writes empty state files so downstream scripts
    # skip tagging. (The old minimal fixture no longer represents "patch
    # disabled" because defaults.yml now sets patch.enabled: true as of v0.6.3.)
    run_calculate "patch-disabled" "hotfix" "" "hotfix: something"
    [ "$status" -eq 0 ]
    # BUMP_TYPE and NEXT_VERSION must be empty (no tag to create)
    echo "$output" | grep -q '^BUMP_TYPE=$'
    echo "$output" | grep -q '^NEXT_VERSION=$'
}

# =============================================================================
# Development release with patch enabled — reset semantics
# =============================================================================

@test "development_release + minor bump (feat): resets patch to 0" {
    # feat now maps to minor in the new SemVer-compatible mapping.
    # with-patch fixture has epoch.enabled=true so version is epoch.major.minor.patch.
    # v0.5.9.3 → epoch=0, major=5, minor=9, patch=3. minor bump → minor=10, patch=0 (omitted).
    run_calculate "with-patch" "development_release" "v0.5.9.3" "feat: new thing"
    [ "$status" -eq 0 ]
    assert_output_matches 'BUMP_TYPE=minor'
    assert_output_matches 'NEXT_VERSION=v0\.5\.10$'
}

@test "development_release + patch bump (fix): does not reset minor" {
    # fix now maps to patch in the new SemVer-compatible mapping
    run_calculate "with-patch" "development_release" "v0.5.9.2" "fix: routine fix"
    [ "$status" -eq 0 ]
    assert_output_matches 'BUMP_TYPE=patch'
    # After patch bump, minor unchanged, patch becomes 3
    assert_output_matches 'NEXT_VERSION=v0\.5\.9\.3$'
}

@test "bump_type.txt contains 'patch' after hotfix bump" {
    run_calculate "with-patch" "hotfix" "v0.5.9" "hotfix: check bump type file"
    [ "$status" -eq 0 ]
    # Explicit grep on the captured BUMP_TYPE line — anchored, no partial matches
    echo "$output" | grep -q '^BUMP_TYPE=patch$'
}

# =============================================================================
# §6.2 — New SemVer-compatible bump mapping cases
# =============================================================================

@test "§6.2 case 1: fix on v1.2.3 yields patch bump → v1.2.4" {
    # fix now maps to patch (SemVer-compatible mapping)
    run_calculate "semver" "development_release" "v1.2.3" "fix: resolve X"
    [ "$status" -eq 0 ]
    assert_output_matches 'BUMP_TYPE=patch'
    assert_output_matches 'NEXT_VERSION=v1\.2\.4$'
}

@test "§6.2 case 2: feat on v1.2.3 yields minor bump → v1.3" {
    # feat now maps to minor (not major) in the new SemVer-compatible mapping.
    # patch=0 is omitted by build_version_string, so v1.3.0 renders as v1.3.
    run_calculate "semver" "development_release" "v1.2.3" "feat: add Y"
    [ "$status" -eq 0 ]
    assert_output_matches 'BUMP_TYPE=minor'
    assert_output_matches 'NEXT_VERSION=v1\.3$'
}

@test "§6.2 case 3: breaking on v1.2.3 yields major bump → v2.0" {
    # breaking still maps to major — no change.
    # patch=0 and minor=0 are omitted, so v2.0.0 renders as v2.0.
    run_calculate "semver" "development_release" "v1.2.3" "breaking: drop Z"
    [ "$status" -eq 0 ]
    assert_output_matches 'BUMP_TYPE=major'
    assert_output_matches 'NEXT_VERSION=v2\.0$'
}

@test "§6.2 case 4: docs commit with timestamp disabled — no tag (none + timestamp off)" {
    # docs maps to none. With timestamp disabled, the pipe must exit-0 and
    # write empty state files so downstream steps skip tagging entirely.
    run_calculate "semver" "development_release" "" "docs: update readme"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^BUMP_TYPE=$'
    echo "$output" | grep -q '^NEXT_VERSION=$'
}

@test "§6.2 case 6: fix on v1.2.3 — patch bump does not reset minor (minor=2 unchanged)" {
    # Verifies that a patch bump leaves the minor component untouched
    run_calculate "semver" "development_release" "v1.2.3" "fix: targeted fix"
    [ "$status" -eq 0 ]
    assert_output_matches 'BUMP_TYPE=patch'
    # Minor must remain 2, not reset to 0
    assert_output_matches 'NEXT_VERSION=v1\.2\.4$'
}

@test "§6.2 case 7: patch component disabled — fix commit does not crash" {
    # patch-disabled fixture has patch.enabled: false. fix: maps to bump: patch,
    # PATCH_PATTERN matches, and the script increments patch internally. However,
    # build_version_string omits the disabled component, producing a degenerate
    # version (e.g. "0.0"). Key requirement: no crash (status=0).
    run_calculate "patch-disabled" "development_release" "" "fix: anything"
    [ "$status" -eq 0 ]
    assert_output_matches 'BUMP_TYPE=patch'
}
