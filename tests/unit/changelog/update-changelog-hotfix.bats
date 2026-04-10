#!/usr/bin/env bats

# update-changelog-hotfix.bats — tests for the hotfix branch-context block in
# scripts/changelog/update-changelog.sh (lines 157-210 at v0.5.5).
#
# The script sources config-parser.sh → auto-loads config. It then reads
# /tmp/scenario.env and, for hotfix_to_main / hotfix_to_preprod, inserts
# /tmp/hotfix_entry.md into the CHANGELOG, commits with a hotfix-specific
# message, and pushes to origin.
#
# Each test sets up a local bare remote so git_push_branch succeeds, writes
# the input state files, then runs the script as a subprocess.

load '../../helpers/setup'
load '../../helpers/assertions'

LOCKFILE="/tmp/.versioning-merged.lock"

setup() { common_setup; }

teardown() {
    common_teardown
    rm -f /tmp/scenario.env /tmp/hotfix_entry.md /tmp/.versioning-merged.yml
}

# Prepare a repo with a bare "origin" remote the script can push to.
# Writes the fixture as .versioning.yml, commits it, wires origin.
prepare_repo_with_remote() {
    local fixture="$1"
    local branch="$2"

    local bare_remote="${BATS_TEST_TMPDIR}/remote.git"
    git init -q --bare "$bare_remote"

    cp "${PIPE_DIR}/tests/fixtures/${fixture}.yml" \
       "${BATS_TEST_TMPDIR}/repo/.versioning.yml"

    cd "${BATS_TEST_TMPDIR}/repo" || return 1

    # Pre-existing CHANGELOG so the sed insertion path runs without the
    # "create new file" branch (which is exercised by hotfix.bats).
    printf '# Changelog\n\n' > CHANGELOG.md

    git add .versioning.yml CHANGELOG.md >/dev/null
    git commit -q -m "chore: initial test state"

    git checkout -q -b "$branch"
    git remote add origin "$bare_remote"
    # Push the branch so subsequent git push origin HEAD:<branch> resolves.
    git push -q origin "$branch"
}

# =============================================================================
# COMMIT MESSAGE FORMAT — branch context (no PR)
# =============================================================================

@test "hotfix_to_main (branch): commit message is 'chore(hotfix): update CHANGELOG for main hotfix'" {
    prepare_repo_with_remote "minimal" "hotfix/urgent-main"

    echo "SCENARIO=hotfix_to_main" > /tmp/scenario.env
    printf '\n## HOTFIX - 2026-04-11\n\n- fix: main hotfix entry\n\n' \
        > /tmp/hotfix_entry.md

    run flock "$LOCKFILE" sh -c "
        cd '${BATS_TEST_TMPDIR}/repo' && \
        VERSIONING_BRANCH='hotfix/urgent-main' \
        sh '${PIPE_DIR}/changelog/update-changelog.sh'
    "

    [ "$status" -eq 0 ]
    last_msg=$(git -C "${BATS_TEST_TMPDIR}/repo" log -1 --pretty=%B)
    echo "$last_msg" | grep -qF "chore(hotfix): update CHANGELOG for main hotfix"
    # Branch context (no PR) → no [skip ci] in the subject line
    ! echo "$last_msg" | head -n 1 | grep -qF "[skip ci]"
}

# =============================================================================
# COMMIT MESSAGE FORMAT — PR context (with VERSIONING_PR_ID)
# =============================================================================

@test "hotfix_to_preprod (PR context): subject includes env name and [skip ci]" {
    prepare_repo_with_remote "minimal" "hotfix/urgent-preprod"

    echo "SCENARIO=hotfix_to_preprod" > /tmp/scenario.env
    printf '\n## HOTFIX - 2026-04-11\n\n- fix: preprod hotfix entry\n\n' \
        > /tmp/hotfix_entry.md

    run flock "$LOCKFILE" sh -c "
        cd '${BATS_TEST_TMPDIR}/repo' && \
        VERSIONING_BRANCH='hotfix/urgent-preprod' \
        VERSIONING_PR_ID='42' \
        sh '${PIPE_DIR}/changelog/update-changelog.sh'
    "

    [ "$status" -eq 0 ]
    subject=$(git -C "${BATS_TEST_TMPDIR}/repo" log -1 --pretty=%s)
    # Default preprod branch is "pre-production", env name is that value.
    echo "$subject" | grep -qF "chore(hotfix): update CHANGELOG for pre-production hotfix"
    # PR context → [skip ci] is present in the subject
    echo "$subject" | grep -qF "[skip ci]"
}

# =============================================================================
# CHANGELOG INSERTION POINT — new section, not merged into latest version
# =============================================================================

@test "hotfix insertion: entry lands at top (line 2), preserving existing content" {
    prepare_repo_with_remote "minimal" "hotfix/insertion-probe"

    # Replace the initial CHANGELOG with one that has a prior version entry.
    # We do this *after* prepare_repo_with_remote so the remote already exists.
    cd "${BATS_TEST_TMPDIR}/repo" || return 1
    printf '# Changelog\n\n## v0.1.0 - 2025-12-01\n\n- existing release line\n\n' \
        > CHANGELOG.md
    git add CHANGELOG.md >/dev/null
    git commit -q -m "chore: seed changelog"
    git push -q origin hotfix/insertion-probe

    echo "SCENARIO=hotfix_to_main" > /tmp/scenario.env
    printf '\n## HOTFIX - 2026-04-11\n\n- fix: new hotfix entry\n\n' \
        > /tmp/hotfix_entry.md

    run flock "$LOCKFILE" sh -c "
        cd '${BATS_TEST_TMPDIR}/repo' && \
        VERSIONING_BRANCH='hotfix/insertion-probe' \
        sh '${PIPE_DIR}/changelog/update-changelog.sh'
    "

    [ "$status" -eq 0 ]

    # The script uses `sed -i "1r /tmp/hotfix_entry.md"` — insertion happens
    # AFTER line 1 (the "# Changelog" header), producing a new Hotfix section
    # that is NOT merged into the v0.1.0 block.
    grep -qF "new hotfix entry" CHANGELOG.md
    grep -qF "existing release line" CHANGELOG.md

    # Verify ordering: the hotfix header appears BEFORE the v0.1.0 header.
    hotfix_line=$(grep -n "## HOTFIX" CHANGELOG.md | head -1 | cut -d: -f1)
    version_line=$(grep -n "## v0.1.0" CHANGELOG.md | head -1 | cut -d: -f1)
    [ "$hotfix_line" -lt "$version_line" ]
}
