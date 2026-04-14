#!/usr/bin/env bats

# Tests for build_ticket_full_pattern and build_bump_pattern
# Sources config-parser.sh, builds patterns, tests with grep -E against real strings

load '../../helpers/setup'
load '../../helpers/assertions'

setup() { common_setup; }
teardown() { common_teardown; }

# =============================================================================
# build_ticket_full_pattern — ticket format (minimal: no prefixes)
# =============================================================================

@test "ticket_full_pattern (minimal): matches 'feat: add login'" {
    source_config_parser "minimal"
    local pattern
    pattern=$(build_ticket_full_pattern)
    echo "feat: add login" | grep -Eq "$pattern"
}

@test "ticket_full_pattern (minimal): matches 'fix: resolve crash'" {
    source_config_parser "minimal"
    local pattern
    pattern=$(build_ticket_full_pattern)
    echo "fix: resolve crash" | grep -Eq "$pattern"
}

@test "ticket_full_pattern (minimal): rejects 'random commit message'" {
    source_config_parser "minimal"
    local pattern
    pattern=$(build_ticket_full_pattern)
    run sh -c "echo 'random commit message' | grep -Eq '$pattern'"
    [ "$status" -ne 0 ]
}

# =============================================================================
# build_ticket_full_pattern — ticket format with prefixes
# =============================================================================

@test "ticket_full_pattern (ticket-based): matches 'AM-123 - feat: add login'" {
    source_config_parser "ticket-based"
    local pattern
    pattern=$(build_ticket_full_pattern)
    echo "AM-123 - feat: add login" | grep -Eq "$pattern"
}

@test "ticket_full_pattern (ticket-based): matches 'TECH-99 - fix: resolve bug'" {
    source_config_parser "ticket-based"
    local pattern
    pattern=$(build_ticket_full_pattern)
    echo "TECH-99 - fix: resolve bug" | grep -Eq "$pattern"
}

@test "ticket_full_pattern (ticket-based): rejects 'WRONG-1 - feat: nope'" {
    source_config_parser "ticket-based"
    local pattern
    pattern=$(build_ticket_full_pattern)
    run sh -c "echo 'WRONG-1 - feat: nope' | grep -Eq '$pattern'"
    [ "$status" -ne 0 ]
}

@test "ticket_full_pattern (ticket-based): rejects bare 'feat: no ticket'" {
    source_config_parser "ticket-based"
    local pattern
    pattern=$(build_ticket_full_pattern)
    run sh -c "echo 'feat: no ticket' | grep -Eq '$pattern'"
    [ "$status" -ne 0 ]
}

# =============================================================================
# build_ticket_full_pattern — conventional format
# =============================================================================

@test "ticket_full_pattern (conventional): matches 'feat: add feature'" {
    source_config_parser "conventional-full"
    local pattern
    pattern=$(build_ticket_full_pattern)
    echo "feat: add feature" | grep -Eq "$pattern"
}

@test "ticket_full_pattern (conventional): matches 'fix(core): resolve issue'" {
    source_config_parser "conventional-full"
    local pattern
    pattern=$(build_ticket_full_pattern)
    echo "fix(core): resolve issue" | grep -Eq "$pattern"
}

@test "ticket_full_pattern (conventional): matches 'chore(release): bump version'" {
    source_config_parser "conventional-full"
    local pattern
    pattern=$(build_ticket_full_pattern)
    echo "chore(release): bump version" | grep -Eq "$pattern"
}

@test "ticket_full_pattern (conventional): rejects 'invalid: not a type'" {
    source_config_parser "conventional-full"
    local pattern
    pattern=$(build_ticket_full_pattern)
    run sh -c "echo 'invalid: not a type' | grep -Eq '$pattern'"
    [ "$status" -ne 0 ]
}

# =============================================================================
# build_bump_pattern — major
# =============================================================================

@test "bump_pattern major (minimal): matches 'feat: new feature'" {
    source_config_parser "minimal"
    local pattern
    pattern=$(build_bump_pattern "major")
    echo "feat: new feature" | grep -Eq "$pattern"
}

@test "bump_pattern major (minimal): matches 'major: breaking change'" {
    source_config_parser "minimal"
    local pattern
    pattern=$(build_bump_pattern "major")
    echo "major: breaking change" | grep -Eq "$pattern"
}

@test "bump_pattern major (minimal): rejects 'fix: minor bug'" {
    source_config_parser "minimal"
    local pattern
    pattern=$(build_bump_pattern "major")
    run sh -c "echo 'fix: minor bug' | grep -Eq '$pattern'"
    [ "$status" -ne 0 ]
}

# =============================================================================
# build_bump_pattern — minor
# =============================================================================

@test "bump_pattern minor (minimal): matches 'fix: bug fix'" {
    source_config_parser "minimal"
    local pattern
    pattern=$(build_bump_pattern "minor")
    echo "fix: bug fix" | grep -Eq "$pattern"
}

@test "bump_pattern minor (minimal): matches 'chore: maintenance'" {
    source_config_parser "minimal"
    local pattern
    pattern=$(build_bump_pattern "minor")
    echo "chore: maintenance" | grep -Eq "$pattern"
}

@test "bump_pattern minor (minimal): rejects 'feat: new feature'" {
    source_config_parser "minimal"
    local pattern
    pattern=$(build_bump_pattern "minor")
    run sh -c "echo 'feat: new feature' | grep -Eq '$pattern'"
    [ "$status" -ne 0 ]
}

# =============================================================================
# build_bump_pattern — conventional with scope
# =============================================================================

@test "bump_pattern major (conventional): matches 'feat(api): new endpoint'" {
    source_config_parser "conventional-full"
    local pattern
    pattern=$(build_bump_pattern "major")
    echo "feat(api): new endpoint" | grep -Eq "$pattern"
}

@test "bump_pattern minor (conventional): matches 'refactor(core): cleanup'" {
    source_config_parser "conventional-full"
    local pattern
    pattern=$(build_bump_pattern "minor")
    echo "refactor(core): cleanup" | grep -Eq "$pattern"
}

# =============================================================================
# build_bump_pattern — ticket-based with prefixes
# =============================================================================

@test "bump_pattern major (ticket-based): matches 'AM-42 - feat: add login'" {
    source_config_parser "ticket-based"
    local pattern
    pattern=$(build_bump_pattern "major")
    echo "AM-42 - feat: add login" | grep -Eq "$pattern"
}

@test "bump_pattern minor (ticket-based): matches 'TECH-7 - fix: patch'" {
    source_config_parser "ticket-based"
    local pattern
    pattern=$(build_bump_pattern "minor")
    echo "TECH-7 - fix: patch" | grep -Eq "$pattern"
}

# =============================================================================
# require_commit_types + changelog.mode coupling
# =============================================================================

@test "require_commit_types: true by default, last_commit mode does not require all" {
    source_config_parser "minimal"
    # require_commit_types is on, but mode is last_commit → for_all is false
    run require_commit_types
    [ "$status" -eq 0 ]
    run require_commit_types_for_all
    [ "$status" -ne 0 ]
}

@test "require_commit_types_for_all: true when mode=full and require_commit_types=true" {
    source_config_parser "conventional-full"
    run require_commit_types_for_all
    [ "$status" -eq 0 ]
}

@test "require_commit_types: false disables validation regardless of changelog.mode" {
    source_config_parser "validation-disabled"
    run require_commit_types
    [ "$status" -ne 0 ]
    run require_commit_types_for_all
    [ "$status" -ne 0 ]
}
