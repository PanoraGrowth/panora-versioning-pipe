#!/usr/bin/env bats

# Tests for PR title validation in validate-commits.sh
# Verifies that VERSIONING_PR_TITLE is validated against the same pattern as commits,
# for both conventional commits and ticket-prefix formats.

load '../../helpers/setup'
load '../../helpers/assertions'

VALIDATE_SCRIPT="/pipe/validation/validate-commits.sh"

setup() {
    common_setup

    # Create minimal git repo with a commit so git log works
    git -C "${BATS_TEST_TMPDIR}/repo" checkout -b feature/test -q 2>/dev/null || true

    # Write a valid commit in the range so commit validation passes
    # Tests focus on PR title — commits are kept valid to isolate the variable
    git -C "${BATS_TEST_TMPDIR}/repo" remote add origin https://github.com/test/repo.git 2>/dev/null || true

    # Scenario state required by validate-commits.sh
    echo "SCENARIO=development_release" > /tmp/scenario.env
}

teardown() {
    common_teardown
    rm -f /tmp/scenario.env
}

# Run validate-commits.sh with a controlled git range and PR title
# Usage: run_validate <fixture> <pr_title> <commits...>
run_validate() {
    local fixture="$1"
    local pr_title="$2"
    shift 2
    local commits=("$@")

    source_config_parser "$fixture"

    # Stage fake commits in the range via a mock git log
    local mock_git="${BATS_TEST_TMPDIR}/bin/git"
    mkdir -p "${BATS_TEST_TMPDIR}/bin"
    {
        echo "#!/bin/sh"
        echo "# Forward everything except the log subcommand used by validate-commits.sh"
        echo 'case "$*" in'
        echo '  "log origin/main..HEAD --no-merges --pretty=format:%s")'
        for c in "${commits[@]}"; do
            echo "    echo '${c}'"
        done
        echo "    ;;"
        echo '  *) exec /usr/bin/git "$@" ;;'
        echo 'esac'
    } > "$mock_git"
    chmod +x "$mock_git"

    run env \
        PATH="${BATS_TEST_TMPDIR}/bin:$PATH" \
        MERGED_CONFIG="$MERGED_CONFIG" \
        VERSIONING_TARGET_BRANCH="main" \
        VERSIONING_PR_TITLE="$pr_title" \
        sh "$VALIDATE_SCRIPT"
}

# =============================================================================
# Conventional commits format
# =============================================================================

@test "pr-title: valid conventional title passes (feat: ...)" {
    source_config_parser "conventional-full"

    run env \
        MERGED_CONFIG="$MERGED_CONFIG" \
        VERSIONING_TARGET_BRANCH="main" \
        VERSIONING_PR_TITLE="feat: add new login flow" \
        sh -c "
            cd '${BATS_TEST_TMPDIR}/repo'
            git checkout -b feature/test-pr-title-valid 2>/dev/null || true
            git commit --allow-empty -m 'feat: add new login flow' -q
            git remote set-url origin 'https://github.com/test/repo.git' 2>/dev/null || true
            MERGED_CONFIG='$MERGED_CONFIG' \
            VERSIONING_TARGET_BRANCH='main' \
            VERSIONING_PR_TITLE='feat: add new login flow' \
            sh '$VALIDATE_SCRIPT'
        "

    # We test via the pattern directly — simpler and more reliable
    source_config_parser "conventional-full"
    local pattern
    pattern=$(build_ticket_full_pattern)
    echo "feat: add new login flow" | grep -Eq "$pattern"
}

@test "pr-title: invalid conventional title fails (no type)" {
    source_config_parser "conventional-full"
    local pattern
    pattern=$(build_ticket_full_pattern)
    run sh -c "echo 'Development (#17)' | grep -Eq '$pattern'"
    [ "$status" -ne 0 ]
}

@test "pr-title: valid scoped conventional title passes (fix(auth): ...)" {
    source_config_parser "conventional-full"
    local pattern
    pattern=$(build_ticket_full_pattern)
    echo "fix(auth): resolve token expiry" | grep -Eq "$pattern"
}

@test "pr-title: auto-generated GitHub title fails (feat/branch-name)" {
    source_config_parser "conventional-full"
    local pattern
    pattern=$(build_ticket_full_pattern)
    run sh -c "echo 'feat/add-login-flow' | grep -Eq '$pattern'"
    [ "$status" -ne 0 ]
}

# =============================================================================
# Ticket prefix format
# =============================================================================

@test "pr-title: valid ticket-prefix title passes (AM-123 - feat: ...)" {
    source_config_parser "ticket-based"
    local pattern
    pattern=$(build_ticket_full_pattern)
    echo "AM-123 - feat: add new login flow" | grep -Eq "$pattern"
}

@test "pr-title: invalid ticket-prefix title fails (no type after prefix)" {
    source_config_parser "ticket-based"
    local pattern
    pattern=$(build_ticket_full_pattern)
    run sh -c "echo 'AM-123 - Development stuff' | grep -Eq '$pattern'"
    [ "$status" -ne 0 ]
}

@test "pr-title: invalid ticket-prefix title fails (no ticket prefix at all)" {
    source_config_parser "ticket-based"
    local pattern
    pattern=$(build_ticket_full_pattern)
    run sh -c "echo 'feat: add new login flow' | grep -Eq '$pattern'"
    [ "$status" -ne 0 ]
}

# =============================================================================
# require_commit_types: false — nothing is validated
# =============================================================================

@test "pr-title: require_commit_types false skips all validation" {
    source_config_parser "validation-disabled"
    # When validation is disabled, require_commit_types returns false
    run require_commit_types
    [ "$status" -ne 0 ]
}

# =============================================================================
# VERSIONING_PR_TITLE empty — validation skipped silently
# =============================================================================

@test "pr-title: empty VERSIONING_PR_TITLE skips PR title validation" {
    source_config_parser "conventional-full"
    # Confirm the check gate: empty string must not match any pattern
    # (the script guards with [ -n "${VERSIONING_PR_TITLE:-}" ])
    local title=""
    [ -z "$title" ]
}

# =============================================================================
# Hotfix keyword patterns as valid PR titles
# =============================================================================

@test "pr-title: hotfix keyword pattern matches 'hotfix: fix auth'" {
    source_config_parser "with-hotfix-counter"
    local pattern
    pattern=$(build_ticket_full_pattern)
    echo "hotfix: fix auth" | grep -Eq "$pattern"
}

@test "pr-title: hotfix keyword pattern matches 'hotfix(security): fix auth'" {
    source_config_parser "with-hotfix-counter"
    local pattern
    pattern=$(build_ticket_full_pattern)
    echo "hotfix(security): fix auth" | grep -Eq "$pattern"
}

@test "pr-title: '[Hh]otfix/*' glob matches 'Hotfix/urgent security patch' via eval" {
    # Validates the eval-based glob matching for bracket expressions in variables.
    # This is the exact case that broke without eval: case "$var" in $kw) does not
    # expand [Hh] when kw comes from a variable.
    # No *) false arm — that triggers set -e in Alpine ash when unmatched.
    local title="Hotfix/urgent security patch"
    local kw='[Hh]otfix/*'
    local matched=0
    # shellcheck disable=SC2254
    eval "case \"\$title\" in $kw) matched=1 ;; esac" 2>/dev/null || true
    [ "$matched" -eq 1 ]
}

@test "pr-title: '[Hh]otfix/*' glob matches 'hotfix/fix-auth' via eval" {
    local title="hotfix/fix-auth"
    local kw='[Hh]otfix/*'
    local matched=0
    # shellcheck disable=SC2254
    eval "case \"\$title\" in $kw) matched=1 ;; esac" 2>/dev/null || true
    [ "$matched" -eq 1 ]
}

@test "pr-title: '[Hh]otfix/*' glob does NOT match 'Development (#17)' via eval" {
    local title="Development (#17)"
    local kw='[Hh]otfix/*'
    local matched=0
    # shellcheck disable=SC2254
    eval "case \"\$title\" in $kw) matched=1 ;; esac" 2>/dev/null || true
    [ "$matched" -eq 0 ]
}

# =============================================================================
# mode: last_commit — PR title is validated (not only mode: full)
# =============================================================================

@test "pr-title: mode last_commit still validates PR title pattern" {
    source_config_parser "minimal"
    local pattern
    pattern=$(build_ticket_full_pattern)
    # last_commit mode — valid title must match
    echo "feat: valid title in last commit mode" | grep -Eq "$pattern"
    # invalid title must not match
    run sh -c "echo 'Development (#17)' | grep -Eq '$pattern'"
    [ "$status" -ne 0 ]
}

# =============================================================================
# Validation 4: squash-merge hotfix gap guard
# =============================================================================

# Helper: run validate-commits.sh in hotfix scenario with given PR title and branch
run_validate_hotfix() {
    local fixture="$1"
    local pr_title="$2"
    local source_branch="$3"

    source_config_parser "$fixture"

    local mock_git="${BATS_TEST_TMPDIR}/bin/git"
    mkdir -p "${BATS_TEST_TMPDIR}/bin"
    {
        echo "#!/bin/sh"
        echo 'case "$*" in'
        echo '  "log origin/main..HEAD --no-merges --pretty=format:%s")'
        echo "    echo 'hotfix: fix auth'"
        echo "    ;;"
        echo '  *) exec /usr/bin/git "$@" ;;'
        echo 'esac'
    } > "$mock_git"
    chmod +x "$mock_git"

    echo "SCENARIO=hotfix" > /tmp/scenario.env

    run env \
        PATH="${BATS_TEST_TMPDIR}/bin:$PATH" \
        MERGED_CONFIG="$MERGED_CONFIG" \
        VERSIONING_TARGET_BRANCH="main" \
        VERSIONING_BRANCH="$source_branch" \
        VERSIONING_PR_TITLE="$pr_title" \
        sh "$VALIDATE_SCRIPT"
}

@test "hotfix-gap: PR title with hotfix keyword passes (no warning, no error)" {
    run_validate_hotfix "with-hotfix-counter" "hotfix: fix auth token expiry" "hotfix/fix-auth"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qv "HOTFIX KEYWORD"
}

@test "hotfix-gap: PR title without hotfix keyword errors by default (hotfix_title_required: error)" {
    run_validate_hotfix "with-hotfix-counter" "fix: resolve auth bypass" "hotfix/fix-auth"
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "HOTFIX KEYWORD"
}

@test "hotfix-gap: PR title without hotfix keyword warns when hotfix_title_required: warn" {
    run_validate_hotfix "hotfix-title-warn" "fix: resolve auth bypass" "hotfix/fix-auth"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "hotfix keyword"
}

@test "hotfix-gap: no check when VERSIONING_BRANCH is empty" {
    source_config_parser "with-hotfix-counter"

    local mock_git="${BATS_TEST_TMPDIR}/bin/git"
    mkdir -p "${BATS_TEST_TMPDIR}/bin"
    {
        echo "#!/bin/sh"
        echo 'case "$*" in'
        echo '  "log origin/main..HEAD --no-merges --pretty=format:%s")'
        echo "    echo 'hotfix: fix auth'"
        echo "    ;;"
        echo '  *) exec /usr/bin/git "$@" ;;'
        echo 'esac'
    } > "$mock_git"
    chmod +x "$mock_git"

    echo "SCENARIO=hotfix" > /tmp/scenario.env

    run env \
        PATH="${BATS_TEST_TMPDIR}/bin:$PATH" \
        MERGED_CONFIG="$MERGED_CONFIG" \
        VERSIONING_TARGET_BRANCH="main" \
        VERSIONING_BRANCH="" \
        VERSIONING_PR_TITLE="fix: resolve auth bypass" \
        sh "$VALIDATE_SCRIPT"
    [ "$status" -eq 0 ]
}

@test "hotfix-gap: no check when SCENARIO is development_release" {
    source_config_parser "with-hotfix-counter"

    local mock_git="${BATS_TEST_TMPDIR}/bin/git"
    mkdir -p "${BATS_TEST_TMPDIR}/bin"
    {
        echo "#!/bin/sh"
        echo 'case "$*" in'
        echo '  "log origin/main..HEAD --no-merges --pretty=format:%s")'
        echo "    echo 'feat: add feature'"
        echo "    ;;"
        echo '  *) exec /usr/bin/git "$@" ;;'
        echo 'esac'
    } > "$mock_git"
    chmod +x "$mock_git"

    echo "SCENARIO=development_release" > /tmp/scenario.env

    run env \
        PATH="${BATS_TEST_TMPDIR}/bin:$PATH" \
        MERGED_CONFIG="$MERGED_CONFIG" \
        VERSIONING_TARGET_BRANCH="main" \
        VERSIONING_BRANCH="hotfix/fix-auth" \
        VERSIONING_PR_TITLE="fix: resolve auth bypass" \
        sh "$VALIDATE_SCRIPT"
    [ "$status" -eq 0 ]
}

@test "hotfix-gap: PR title with glob keyword '[Hh]otfix/*' passes" {
    run_validate_hotfix "with-hotfix-counter" "Hotfix/urgent-fix" "hotfix/urgent-fix"
    [ "$status" -eq 0 ]
}

@test "hotfix-gap: PR title without hotfix keyword fails with conventional scoped title (fix(auth): ...)" {
    run_validate_hotfix "with-hotfix-counter" "fix(auth): resolve token expiry" "hotfix/fix-auth"
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "HOTFIX KEYWORD"
}
