#!/usr/bin/env bats

# hotfix-branch-context.bats — tests for detect-scenario.sh in branch context
#
# Branch context = called by branch-pipeline.sh after a merge, with no PR
# target. Hotfix detection uses:
#   1. Commit type convention (primary) — subject starts with hotfix: / hotfix(
#   2. GitHub API PR lookup (fallback) — head ref matches hotfix prefix
# These tests exercise both paths via a shell stub for gh.

load '../../helpers/setup'
load '../../helpers/assertions'

LOCKFILE="/tmp/.versioning-merged.lock"

setup() { common_setup; }

teardown() {
    common_teardown
    rm -f /tmp/scenario.env /tmp/.versioning-merged.yml
    unset GITHUB_REPOSITORY
}

# Seed the repo with a fixture and a HEAD commit carrying the given subject,
# then run detect-scenario.sh in branch context (no TARGET_BRANCH) and return
# the exit status + stdout via `run`. The scenario lands in /tmp/scenario.env.
run_detect_branch() {
    local fixture="$1"
    local commit_subject="$2"
    local extra_env="${3:-}"

    cp "${PIPE_DIR}/tests/fixtures/${fixture}.yml" \
       "${BATS_TEST_TMPDIR}/repo/.versioning.yml"

    cd "${BATS_TEST_TMPDIR}/repo" || return 1

    echo "artifact" > artifact.txt
    git add artifact.txt .versioning.yml >/dev/null
    git commit -q -m "$commit_subject"

    run flock "$LOCKFILE" sh -c "
        cd '${BATS_TEST_TMPDIR}/repo' && \
        unset VERSIONING_TARGET_BRANCH && \
        VERSIONING_BRANCH='main' \
        VERSIONING_COMMIT=\$(git rev-parse HEAD) \
        ${extra_env} \
        sh '${PIPE_DIR}/detection/detect-scenario.sh'
    "
}

# Build a fake `gh` binary that pretends to be authenticated and returns a
# hard-coded head ref for any `gh api ...` call. The stub lives in the test's
# temp dir and is shadowed from PATH via extra_env.
install_gh_stub() {
    local head_ref="$1"
    local stub_dir="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "$stub_dir"
    cat > "${stub_dir}/gh" <<STUB
#!/bin/sh
# Fake gh — returns the head ref and ignores --jq (the caller already selected it)
echo "${head_ref}"
STUB
    chmod +x "${stub_dir}/gh"
    echo "$stub_dir"
}

# =============================================================================
# Primary detection: commit type convention
# =============================================================================

@test "branch context: 'hotfix: fix bug' → hotfix_to_main" {
    run_detect_branch "minimal" "hotfix: fix auth bypass"
    [ "$status" -eq 0 ]
    grep -q '^SCENARIO=hotfix_to_main$' /tmp/scenario.env
}

@test "branch context: 'hotfix(security): ...' → hotfix_to_main (scoped form)" {
    run_detect_branch "minimal" "hotfix(security): patch credential leak"
    [ "$status" -eq 0 ]
    grep -q '^SCENARIO=hotfix_to_main$' /tmp/scenario.env
}

@test "branch context: 'feat: new feature' → development_release" {
    run_detect_branch "minimal" "feat: new shiny thing"
    [ "$status" -eq 0 ]
    grep -q '^SCENARIO=development_release$' /tmp/scenario.env
}

@test "branch context: plain 'fix: ...' → development_release (not hotfix)" {
    run_detect_branch "minimal" "fix: routine bug fix"
    [ "$status" -eq 0 ]
    grep -q '^SCENARIO=development_release$' /tmp/scenario.env
}

# =============================================================================
# Fallback detection: GitHub API PR head ref
# =============================================================================

@test "branch context: gh API fallback — hotfix/ head ref → hotfix_to_main" {
    local stub_dir
    stub_dir=$(install_gh_stub "hotfix/critical-auth")
    # Subject does NOT carry the signal; the API fallback must catch it.
    # Unquoted PATH so the inner sh expands $PATH to its own value.
    run_detect_branch "minimal" "chore: merge hotfix branch" \
        "PATH=${stub_dir}:\$PATH GITHUB_REPOSITORY=acme/app"
    [ "$status" -eq 0 ]
    grep -q '^SCENARIO=hotfix_to_main$' /tmp/scenario.env
}

@test "branch context: gh API fallback — feature/ head ref → development_release" {
    local stub_dir
    stub_dir=$(install_gh_stub "feature/new-thing")
    run_detect_branch "minimal" "chore: merge feature branch" \
        "PATH=${stub_dir}:\$PATH GITHUB_REPOSITORY=acme/app"
    [ "$status" -eq 0 ]
    grep -q '^SCENARIO=development_release$' /tmp/scenario.env
}

# =============================================================================
# Regression: PR context path still works (existing target-branch dispatch)
# =============================================================================

@test "PR context regression: hotfix/* → main still returns hotfix_to_main" {
    cp "${PIPE_DIR}/tests/fixtures/minimal.yml" \
       "${BATS_TEST_TMPDIR}/repo/.versioning.yml"
    cd "${BATS_TEST_TMPDIR}/repo" || return 1

    run flock "$LOCKFILE" sh -c "
        cd '${BATS_TEST_TMPDIR}/repo' && \
        VERSIONING_BRANCH='hotfix/auth-fix' \
        VERSIONING_TARGET_BRANCH='main' \
        sh '${PIPE_DIR}/detection/detect-scenario.sh'
    "
    [ "$status" -eq 0 ]
    grep -q '^SCENARIO=hotfix_to_main$' /tmp/scenario.env
}
