#!/usr/bin/env bats

# commit-type-bumps.bats — bump validation per commit type (core + extended)
#
# Each test verifies that a specific commit type triggers the expected BUMP_TYPE.
# Uses the semver fixture (v-prefix, epoch off, major+patch, no timestamp) as
# baseline, starting from tag v1.0 so version arithmetic is unambiguous.
#
# Extended types are registered in the global commit-types.yml (via defaults.yml)
# so they are available without any commit_type_overrides configuration.

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
    local fixture="$1"
    local scenario="$2"
    local initial_tag="$3"
    local commit_msg="$4"

    cp "${PIPE_DIR}/tests/fixtures/${fixture}.yml" \
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

# =============================================================================
# Core types — minor bump (feat alias)
# =============================================================================

@test "feature: produces minor bump" {
    run_calculate "semver" "development_release" "v1.0" "feature: new capability"
    [ "$status" -eq 0 ]
    assert_output_matches 'BUMP_TYPE=minor'
}

# =============================================================================
# Core types — patch bump
# =============================================================================

@test "hotfix: produces patch bump" {
    run_calculate "semver" "development_release" "v1.0" "hotfix: urgent fix"
    [ "$status" -eq 0 ]
    assert_output_matches 'BUMP_TYPE=patch'
}

@test "security: produces patch bump" {
    run_calculate "semver" "development_release" "v1.0" "security: patch CVE"
    [ "$status" -eq 0 ]
    assert_output_matches 'BUMP_TYPE=patch'
}

@test "revert: produces patch bump" {
    run_calculate "semver" "development_release" "v1.0" "revert: undo bad change"
    [ "$status" -eq 0 ]
    assert_output_matches 'BUMP_TYPE=patch'
}

@test "perf: produces patch bump" {
    run_calculate "semver" "development_release" "v1.0" "perf: speed up query"
    [ "$status" -eq 0 ]
    assert_output_matches 'BUMP_TYPE=patch'
}

# =============================================================================
# Core types — none bump (no tag produced)
# =============================================================================

@test "refactor: produces no bump (empty state files)" {
    run_calculate "semver" "development_release" "" "refactor: extract helper"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^BUMP_TYPE=$'
    echo "$output" | grep -q '^NEXT_VERSION=$'
}

@test "docs: produces no bump (empty state files)" {
    run_calculate "semver" "development_release" "" "docs: update readme"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^BUMP_TYPE=$'
    echo "$output" | grep -q '^NEXT_VERSION=$'
}

@test "test: produces no bump (empty state files)" {
    run_calculate "semver" "development_release" "" "test: add unit coverage"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^BUMP_TYPE=$'
    echo "$output" | grep -q '^NEXT_VERSION=$'
}

@test "chore: produces no bump (empty state files)" {
    run_calculate "semver" "development_release" "" "chore: clean up temp files"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^BUMP_TYPE=$'
    echo "$output" | grep -q '^NEXT_VERSION=$'
}

@test "build: produces no bump (empty state files)" {
    run_calculate "semver" "development_release" "" "build: upgrade docker base"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^BUMP_TYPE=$'
    echo "$output" | grep -q '^NEXT_VERSION=$'
}

@test "ci: produces no bump (empty state files)" {
    run_calculate "semver" "development_release" "" "ci: add lint step"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^BUMP_TYPE=$'
    echo "$output" | grep -q '^NEXT_VERSION=$'
}

@test "style: produces no bump (empty state files)" {
    run_calculate "semver" "development_release" "" "style: reformat whitespace"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^BUMP_TYPE=$'
    echo "$output" | grep -q '^NEXT_VERSION=$'
}

# =============================================================================
# Extended types — patch bump
# =============================================================================

@test "infra: produces patch bump" {
    run_calculate "semver" "development_release" "v1.0" "infra: update k8s manifests"
    [ "$status" -eq 0 ]
    assert_output_matches 'BUMP_TYPE=patch'
}

@test "deploy: produces patch bump" {
    run_calculate "semver" "development_release" "v1.0" "deploy: ship to production"
    [ "$status" -eq 0 ]
    assert_output_matches 'BUMP_TYPE=patch'
}

@test "deps: produces patch bump" {
    run_calculate "semver" "development_release" "v1.0" "deps: bump lodash to 4.17.21"
    [ "$status" -eq 0 ]
    assert_output_matches 'BUMP_TYPE=patch'
}

@test "migration: produces patch bump" {
    run_calculate "semver" "development_release" "v1.0" "migration: add users table index"
    [ "$status" -eq 0 ]
    assert_output_matches 'BUMP_TYPE=patch'
}

@test "rollback: produces patch bump" {
    run_calculate "semver" "development_release" "v1.0" "rollback: revert bad deploy"
    [ "$status" -eq 0 ]
    assert_output_matches 'BUMP_TYPE=patch'
}

@test "data: produces patch bump" {
    run_calculate "semver" "development_release" "v1.0" "data: seed production data"
    [ "$status" -eq 0 ]
    assert_output_matches 'BUMP_TYPE=patch'
}

@test "regulatory: produces patch bump" {
    run_calculate "semver" "development_release" "v1.0" "regulatory: GDPR consent field"
    [ "$status" -eq 0 ]
    assert_output_matches 'BUMP_TYPE=patch'
}

@test "iac: produces patch bump" {
    run_calculate "semver" "development_release" "v1.0" "iac: terraform modules update"
    [ "$status" -eq 0 ]
    assert_output_matches 'BUMP_TYPE=patch'
}

# =============================================================================
# Extended types — none bump
# =============================================================================

@test "config: produces no bump (empty state files)" {
    run_calculate "semver" "development_release" "" "config: update env vars"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^BUMP_TYPE=$'
    echo "$output" | grep -q '^NEXT_VERSION=$'
}

@test "compliance: produces no bump (empty state files)" {
    run_calculate "semver" "development_release" "" "compliance: internal audit req"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^BUMP_TYPE=$'
    echo "$output" | grep -q '^NEXT_VERSION=$'
}

@test "audit: produces no bump (empty state files)" {
    run_calculate "semver" "development_release" "" "audit: add trace logging"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^BUMP_TYPE=$'
    echo "$output" | grep -q '^NEXT_VERSION=$'
}

@test "release: produces no bump (empty state files)" {
    run_calculate "semver" "development_release" "" "release: v1.0.0"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^BUMP_TYPE=$'
    echo "$output" | grep -q '^NEXT_VERSION=$'
}

@test "wip: produces no bump (empty state files)" {
    run_calculate "semver" "development_release" "" "wip: draft implementation"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^BUMP_TYPE=$'
    echo "$output" | grep -q '^NEXT_VERSION=$'
}

@test "experiment: produces no bump (empty state files)" {
    run_calculate "semver" "development_release" "" "experiment: spike new algo"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^BUMP_TYPE=$'
    echo "$output" | grep -q '^NEXT_VERSION=$'
}
