#!/usr/bin/env bats

# bump-strategy.bats — verify bump selection strategy tied to changelog.mode
#
# changelog.mode=last_commit → last commit wins (backward-compatible default)
# changelog.mode=full        → highest-ranked commit wins across all commits
#
# Rank: major(3) > minor(2) > patch(1) > timestamp_only(0)

load '../../helpers/setup'
load '../../helpers/assertions'

LOCKFILE="/tmp/.versioning-merged.lock"

setup() { common_setup; }

teardown() {
    common_teardown
    rm -f /tmp/scenario.env /tmp/.versioning-merged.yml \
          /tmp/next_version.txt /tmp/bump_type.txt /tmp/latest_tag.txt
}

# Helper: create repo with multiple commits and run calculate-version.sh
# Args: fixture, initial_tag, commit_msgs (space-separated, use __ for spaces within msg)
run_multi_commit() {
    local fixture="$1"
    local initial_tag="$2"
    shift 2

    cp "${PIPE_DIR}/tests/fixtures/${fixture}.yml" \
       "${BATS_TEST_TMPDIR}/repo/.versioning.yml"

    cd "${BATS_TEST_TMPDIR}/repo" || return 1

    if [ -n "$initial_tag" ]; then
        git tag "$initial_tag"
    fi

    local i=0
    for msg in "$@"; do
        i=$((i + 1))
        echo "artifact${i}" > "artifact${i}.txt"
        git add "artifact${i}.txt" .versioning.yml >/dev/null
        git commit -q -m "$msg"
    done

    run flock "$LOCKFILE" sh -c "
        echo 'SCENARIO=development_release' > /tmp/scenario.env ; \
        cd '${BATS_TEST_TMPDIR}/repo' && \
        sh '${PIPE_DIR}/versioning/calculate-version.sh' >/dev/null 2>&1 ; \
        echo BUMP_TYPE=\$(cat /tmp/bump_type.txt 2>/dev/null) ; \
        echo NEXT_VERSION=\$(cat /tmp/next_version.txt 2>/dev/null)
    "
}

# =============================================================================
# last_commit strategy (semver fixture — mode: last_commit by default)
# =============================================================================

@test "last_commit: fix then feat — last commit (feat) determines bump → minor" {
    run_multi_commit "semver" "v1.0" \
        "fix: first fix" \
        "feat: feature is last"
    [ "$status" -eq 0 ]
    assert_output_matches 'BUMP_TYPE=minor'
}

@test "last_commit: feat then fix — last commit (fix) determines bump → patch" {
    run_multi_commit "semver" "v1.0" \
        "feat: feature is first" \
        "fix: fix is last"
    [ "$status" -eq 0 ]
    assert_output_matches 'BUMP_TYPE=patch'
}

@test "last_commit: single commit — same result regardless of strategy" {
    run_multi_commit "semver" "v1.0" \
        "feat: only commit"
    [ "$status" -eq 0 ]
    assert_output_matches 'BUMP_TYPE=minor'
}

# =============================================================================
# full strategy (conventional-full fixture — mode: full)
# =============================================================================

@test "full: fix feat fix — highest (feat) wins → minor bump" {
    run_multi_commit "conventional-full" "v1.0" \
        "fix: first fix" \
        "feat: feature in the middle" \
        "fix: last fix"
    [ "$status" -eq 0 ]
    assert_output_matches 'BUMP_TYPE=minor'
}

@test "full: feat then fix — highest (feat) wins even when fix is last → minor bump" {
    run_multi_commit "conventional-full" "v1.0" \
        "feat: feature is first" \
        "fix: fix is last"
    [ "$status" -eq 0 ]
    assert_output_matches 'BUMP_TYPE=minor'
}

@test "full: fix chore fix — highest (fix) wins → patch bump" {
    run_multi_commit "conventional-full" "v1.0" \
        "fix: first fix" \
        "chore: no bump" \
        "chore: also no bump"
    [ "$status" -eq 0 ]
    assert_output_matches 'BUMP_TYPE=patch'
}

@test "full: single commit — same result as last_commit" {
    run_multi_commit "conventional-full" "v1.0" \
        "feat: only commit"
    [ "$status" -eq 0 ]
    assert_output_matches 'BUMP_TYPE=minor'
}

@test "full: none-bump commits only — no version produced" {
    run_multi_commit "conventional-full" "" \
        "chore: no bump" \
        "docs: also no bump"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^BUMP_TYPE=$'
    echo "$output" | grep -q '^NEXT_VERSION=$'
}
