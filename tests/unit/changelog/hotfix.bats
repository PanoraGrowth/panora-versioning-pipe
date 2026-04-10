#!/usr/bin/env bats

# hotfix.bats — tests for scripts/changelog/generate-hotfix-changelog.sh
#
# The hotfix changelog generator is invoked as a subprocess (not sourced),
# so each test sets up an isolated git repo, writes /tmp/scenario.env,
# then runs /pipe/changelog/generate-hotfix-changelog.sh.
#
# Like detection/scenarios.bats, we use flock on the merged-config path to
# serialize parallel job execution — the script sources config-parser.sh
# which writes to /tmp/.versioning-merged.yml on source.

load '../../helpers/setup'
load '../../helpers/assertions'

LOCKFILE="/tmp/.versioning-merged.lock"

setup() { common_setup; }

teardown() {
    common_teardown
    rm -f /tmp/scenario.env /tmp/.versioning-merged.yml
}

# Helper: prepare repo with fixture and a single commit, then run the generator
# Usage: run_hotfix_generator <fixture> <scenario> <commit_message>
run_hotfix_generator() {
    local fixture="$1"
    local scenario="$2"
    local commit_msg="$3"

    cp "${PIPE_DIR}/tests/fixtures/${fixture}.yml" \
       "${BATS_TEST_TMPDIR}/repo/.versioning.yml"

    cd "${BATS_TEST_TMPDIR}/repo" || return 1

    # Ensure there is a commit we can point at
    echo "artifact" > artifact.txt
    git add artifact.txt .versioning.yml >/dev/null
    git commit -q -m "$commit_msg"

    echo "SCENARIO=${scenario}" > /tmp/scenario.env

    run flock "$LOCKFILE" sh -c "
        cd '${BATS_TEST_TMPDIR}/repo' && \
        sh '${PIPE_DIR}/changelog/generate-hotfix-changelog.sh'
    "
}

# =============================================================================
# HAPPY PATH
# =============================================================================

@test "happy path: hotfix_to_main produces CHANGELOG with hotfix entry" {
    run_hotfix_generator "minimal" "hotfix_to_main" "fix: resolve critical auth bug"

    [ "$status" -eq 0 ]
    [ -f "${BATS_TEST_TMPDIR}/repo/CHANGELOG.md" ]
    grep -q "fix: resolve critical auth bug" "${BATS_TEST_TMPDIR}/repo/CHANGELOG.md"
}

# =============================================================================
# HEADER FORMAT
# =============================================================================

@test "header format: uses '## HOTFIX - DATE' by default" {
    run_hotfix_generator "minimal" "hotfix_to_main" "fix: header check"

    [ "$status" -eq 0 ]
    # Default hotfix.changelog_header is "HOTFIX" (scripts/defaults.yml).
    # Format is "## ${HOTFIX_HEADER} - ${COMMIT_DATE}".
    grep -qE "^## HOTFIX - [0-9]{4}-[0-9]{2}-[0-9]{2}$" "${BATS_TEST_TMPDIR}/repo/CHANGELOG.md"
}

# =============================================================================
# TICKET PREFIX EXTRACTION
# =============================================================================

@test "ticket prefix: extracts AM-123 from 'AM-123 - Fix bug'" {
    run_hotfix_generator "ticket-based" "hotfix_to_main" "AM-123 - Fix login redirect"

    [ "$status" -eq 0 ]
    # When a ticket is detected, the line is rendered as:
    #   - **AM-123** - Fix login redirect
    grep -qF "**AM-123** - Fix login redirect" "${BATS_TEST_TMPDIR}/repo/CHANGELOG.md"
}

@test "ticket prefix: no prefixes configured → renders plain line" {
    run_hotfix_generator "minimal" "hotfix_to_main" "fix: no ticket here"

    [ "$status" -eq 0 ]
    # Without prefixes configured, the else branch hits: "- ${LAST_COMMIT}"
    grep -qF -e "- fix: no ticket here" "${BATS_TEST_TMPDIR}/repo/CHANGELOG.md"
    # And the bold ticket form is NOT present
    ! grep -qF "**" "${BATS_TEST_TMPDIR}/repo/CHANGELOG.md"
}

# =============================================================================
# EMOJI MODE (current behavior: the hotfix generator does NOT render emojis)
# =============================================================================

@test "emoji mode: enabled in config but hotfix generator does not render emojis" {
    run_hotfix_generator "conventional-full" "hotfix_to_main" "fix: emoji probe"

    [ "$status" -eq 0 ]
    # conventional-full.yml sets changelog.use_emojis: true, but the hotfix
    # generator does not consult that flag — it always renders a plain bullet.
    # This test locks in current behavior so future changes are explicit.
    grep -qF -e "- fix: emoji probe" "${BATS_TEST_TMPDIR}/repo/CHANGELOG.md"
    ! grep -qF "🐛" "${BATS_TEST_TMPDIR}/repo/CHANGELOG.md"
    ! grep -qF "🚑" "${BATS_TEST_TMPDIR}/repo/CHANGELOG.md"
}

# =============================================================================
# MULTIPLE COMMITS — last-commit-only semantics
# =============================================================================

@test "multiple commits: only the most recent hotfix commit is included" {
    cp "${PIPE_DIR}/tests/fixtures/minimal.yml" \
       "${BATS_TEST_TMPDIR}/repo/.versioning.yml"
    cd "${BATS_TEST_TMPDIR}/repo" || return 1

    echo "a" > a.txt; git add a.txt .versioning.yml >/dev/null
    git commit -q -m "fix: first hotfix attempt"
    echo "b" > b.txt; git add b.txt >/dev/null
    git commit -q -m "fix: second and final hotfix"

    echo "SCENARIO=hotfix_to_main" > /tmp/scenario.env

    run flock "$LOCKFILE" sh -c "
        cd '${BATS_TEST_TMPDIR}/repo' && \
        sh '${PIPE_DIR}/changelog/generate-hotfix-changelog.sh'
    "

    [ "$status" -eq 0 ]
    # The generator uses LAST_COMMIT=$(echo "$COMMITS" | head -n 1) which takes
    # the most recent commit. Only that one should appear in the CHANGELOG.
    grep -qF "second and final hotfix" "${BATS_TEST_TMPDIR}/repo/CHANGELOG.md"
    ! grep -qF "first hotfix attempt" "${BATS_TEST_TMPDIR}/repo/CHANGELOG.md"
}

# =============================================================================
# SCENARIO GUARD
# =============================================================================

@test "non-hotfix scenario: early exit without writing CHANGELOG" {
    run_hotfix_generator "minimal" "development_release" "feat: not a hotfix"

    [ "$status" -eq 0 ]
    [ ! -f "${BATS_TEST_TMPDIR}/repo/CHANGELOG.md" ]
}

# =============================================================================
# CHANGELOG CREATE vs APPEND
# =============================================================================

@test "no CHANGELOG exists: script creates it with title header" {
    run_hotfix_generator "minimal" "hotfix_to_main" "fix: create from scratch"

    [ "$status" -eq 0 ]
    # Default changelog.title is "Changelog"
    grep -qE "^# Changelog$" "${BATS_TEST_TMPDIR}/repo/CHANGELOG.md"
    grep -qF "create from scratch" "${BATS_TEST_TMPDIR}/repo/CHANGELOG.md"
}

@test "CHANGELOG exists: hotfix entry is appended, previous content preserved" {
    cp "${PIPE_DIR}/tests/fixtures/minimal.yml" \
       "${BATS_TEST_TMPDIR}/repo/.versioning.yml"
    cd "${BATS_TEST_TMPDIR}/repo" || return 1

    # Pre-existing CHANGELOG with a sentinel line
    printf '# Changelog\n\n---\n\n## v1.0.0 - 2025-01-01\n\n- previous release entry\n\n' \
        > CHANGELOG.md
    git add .versioning.yml CHANGELOG.md >/dev/null
    git commit -q -m "fix: append probe"

    echo "SCENARIO=hotfix_to_main" > /tmp/scenario.env

    run flock "$LOCKFILE" sh -c "
        cd '${BATS_TEST_TMPDIR}/repo' && \
        sh '${PIPE_DIR}/changelog/generate-hotfix-changelog.sh'
    "

    [ "$status" -eq 0 ]
    # Old content is still there
    grep -qF "previous release entry" CHANGELOG.md
    # New hotfix entry was added
    grep -qF "append probe" CHANGELOG.md
}
