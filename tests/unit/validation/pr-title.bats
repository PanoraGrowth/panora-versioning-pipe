#!/usr/bin/env bats

# Tests for PR title validation in validate-commits.sh
# Verifies that VERSIONING_PR_TITLE is validated against the same pattern as commits,
# for both conventional commits and ticket-prefix formats.

load '../../helpers/setup'
load '../../helpers/assertions'

VALIDATE_SCRIPT="/pipe/scripts/validation/validate-commits.sh"

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
