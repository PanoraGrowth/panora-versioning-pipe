#!/usr/bin/env bats

# Tests for scripts/validation/guardrails.sh
# Validates that assert_no_version_regression enforces the correct per-bump-type
# rules and emits structured GUARDRAIL log lines to stderr.
#
# Bump-type rules under test:
#   epoch  → next.epoch > latest.epoch (strict)
#   major  → next.major > latest.major strict + epoch sanity >=
#   patch  → next.patch > latest.patch strict + major/epoch sanity >=
#   hotfix → same base: counter strict; base changed: base components >=
#
# Setup: each test writes /tmp/next_version.txt, /tmp/latest_tag.txt,
#        /tmp/bump_type.txt directly (no git, no pipe subprocess).

load '../../helpers/setup'
load '../../helpers/assertions'

GUARDRAILS_SCRIPT="/pipe/validation/guardrails.sh"

# Helper: write state files and run assert_no_version_regression in isolation.
# Uses BATS_TEST_TMPDIR-scoped state files to avoid /tmp races in parallel runs.
# Args: fixture, next_tag, latest_tag, bump_type
run_guardrail() {
    local fixture="$1"
    local next_tag="$2"
    local latest_tag="$3"
    local bump_type="$4"

    source_config_parser "$fixture"

    local next_f="${BATS_TEST_TMPDIR}/next_version.txt"
    local latest_f="${BATS_TEST_TMPDIR}/latest_tag.txt"
    local bump_f="${BATS_TEST_TMPDIR}/bump_type.txt"

    printf '%s\n' "$next_tag"   > "$next_f"
    printf '%s\n' "$latest_tag" > "$latest_f"
    printf '%s\n' "$bump_type"  > "$bump_f"

    # Source the guardrail hub and call the function directly.
    # Override read_state to read from test-scoped files instead of /tmp.
    run sh -c "
        . /pipe/lib/common.sh
        MERGED_CONFIG='${MERGED_CONFIG}'
        export MERGED_CONFIG
        . /pipe/lib/config-parser.sh

        # Override read_state to use test-scoped files
        read_state() {
            local f=\"\$1\"
            case \"\$f\" in
                /tmp/next_version.txt) f='${next_f}' ;;
                /tmp/latest_tag.txt)  f='${latest_f}' ;;
                /tmp/bump_type.txt)   f='${bump_f}' ;;
            esac
            [ -f \"\$f\" ] && cat \"\$f\" || return 1
        }

        . ${GUARDRAILS_SCRIPT}
        assert_no_version_regression
    "
}

setup() {
    common_setup
}

teardown() {
    common_teardown
    # State files live in BATS_TEST_TMPDIR — cleaned up by common_teardown
}

# =============================================================================
# COLD START — no latest tag
# =============================================================================

@test "guardrail: cold start (no latest tag) → pass" {
    run_guardrail "with-v-prefix" "v5.1.0" "" "major"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "result=pass"
    echo "$output" | grep -q "reason=cold_start"
}

# =============================================================================
# MAJOR bump (feat)
# epoch=off: tags are v{major}.{patch}.{hotfix_counter}
# major bump: first component increments (v5.* → v6.*)
# =============================================================================

@test "guardrail: major bump — major increments (v5.2.0 → v6.1.0) → pass" {
    run_guardrail "with-v-prefix" "v6.1.0" "v5.2.0" "major"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "result=pass"
    echo "$output" | grep -q "bump=major"
}

@test "guardrail: major bump — major did not increment (v5.2.0 → v5.3.0) → block" {
    # bump=major but only patch changed (5→5 same, 2→3 is patch position)
    run_guardrail "with-v-prefix" "v5.3.0" "v5.2.0" "major"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "result=blocked"
    echo "$output" | grep -q "violation=major_not_incremented"
}

@test "guardrail: major bump — epoch regressed → block" {
    # epoch enabled: latest v1.5.0 next v0.6.0 (epoch dropped from 1 to 0)
    source_config_parser "all-components"
    local next_f="${BATS_TEST_TMPDIR}/next_version.txt"
    local latest_f="${BATS_TEST_TMPDIR}/latest_tag.txt"
    local bump_f="${BATS_TEST_TMPDIR}/bump_type.txt"
    printf 'v0.6.0\n' > "$next_f"
    printf 'v1.5.0\n' > "$latest_f"
    printf 'major\n'  > "$bump_f"
    run sh -c "
        . /pipe/lib/common.sh
        MERGED_CONFIG='${MERGED_CONFIG}'
        export MERGED_CONFIG
        . /pipe/lib/config-parser.sh
        read_state() {
            local f=\"\$1\"
            case \"\$f\" in
                /tmp/next_version.txt) f='${next_f}' ;;
                /tmp/latest_tag.txt)  f='${latest_f}' ;;
                /tmp/bump_type.txt)   f='${bump_f}' ;;
            esac
            [ -f \"\$f\" ] && cat \"\$f\" || return 1
        }
        . ${GUARDRAILS_SCRIPT}
        assert_no_version_regression
    "
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "result=blocked"
    echo "$output" | grep -q "violation=epoch_regressed"
}

# =============================================================================
# PATCH bump (fix)
# epoch=off: tags are v{major}.{patch}.{hotfix_counter}
# patch bump: second component increments (v5.2.* → v5.3.*)
# =============================================================================

@test "guardrail: patch bump — patch increments (v5.2.0 → v5.3.0) → pass" {
    run_guardrail "with-v-prefix" "v5.3.0" "v5.2.0" "patch"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "result=pass"
    echo "$output" | grep -q "bump=patch"
}

@test "guardrail: patch bump — patch did not increment (same tag) → block" {
    run_guardrail "with-v-prefix" "v5.2.0" "v5.2.0" "patch"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "result=blocked"
    echo "$output" | grep -q "violation=patch_not_incremented"
}

@test "guardrail: patch bump — major regressed → block" {
    # bump=patch but major dropped (5→4)
    run_guardrail "with-v-prefix" "v4.3.0" "v5.2.0" "patch"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "result=blocked"
    echo "$output" | grep -q "violation=major_regressed"
}

# =============================================================================
# HOTFIX bump
# with-hotfix-counter: epoch=on, initial=0 → tags are v{epoch}.{major}.{patch}.{hotfix_counter}
# Mirror of production use (pipe self-versioning: v0.5.9 → v0.5.9.1)
# =============================================================================

@test "guardrail: hotfix bump — same base, counter increments (v0.5.9 → v0.5.9.1) → pass" {
    run_guardrail "with-hotfix-counter" "v0.5.9.1" "v0.5.9" "hotfix"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "result=pass"
}

@test "guardrail: hotfix bump — same base, counter increments again (v0.5.9.1 → v0.5.9.2) → pass" {
    run_guardrail "with-hotfix-counter" "v0.5.9.2" "v0.5.9.1" "hotfix"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "result=pass"
}

@test "guardrail: hotfix bump — same base, counter did not increment → block" {
    run_guardrail "with-hotfix-counter" "v0.5.9.1" "v0.5.9.1" "hotfix"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "result=blocked"
    echo "$output" | grep -q "violation=hotfix_counter_not_incremented"
}

@test "guardrail: hotfix bump — base changed (major up, counter reset to 1) → pass" {
    # After v0.5.9.3 (3 hotfixes on v0.5.9), a feat shipped v0.6.0.
    # Hotfix against v0.6.0 → v0.6.0.1. major changed (5→6), counter reset 3→1 — valid.
    run_guardrail "with-hotfix-counter" "v0.6.0.1" "v0.5.9.3" "hotfix"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "result=pass"
}

@test "guardrail: hotfix bump — base changed but major regressed → block" {
    # Bug: bump=hotfix but computed tag has lower major
    # latest v0.6.0.2, next v0.5.9.1 — major dropped from 6 to 5
    run_guardrail "with-hotfix-counter" "v0.5.9.1" "v0.6.0.2" "hotfix"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "result=blocked"
    echo "$output" | grep -q "violation=major_regressed"
}

# =============================================================================
# allow_version_regression override — degrades block to warning (exit 2)
# =============================================================================

@test "guardrail: regression with allow_version_regression=true → warned (exit 2)" {
    # patch did not increment — with default config this would block
    # with allow_version_regression=true it degrades to warning (exit 2)
    run_guardrail "guardrails-allow-regression" "v5.2.0" "v5.2.0" "patch"
    [ "$status" -eq 2 ]
    echo "$output" | grep -q "result=warned"
    echo "$output" | grep -q "override=allow_version_regression"
}

# =============================================================================
# Structured log format
# =============================================================================

@test "guardrail: structured log line always emitted on pass" {
    run_guardrail "with-v-prefix" "v6.1.0" "v5.2.0" "major"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qE "^GUARDRAIL name=no_version_regression result=pass"
}

@test "guardrail: structured log line always emitted on block" {
    run_guardrail "with-v-prefix" "v5.3.0" "v5.2.0" "major"
    [ "$status" -eq 1 ]
    echo "$output" | grep -qE "^GUARDRAIL name=no_version_regression result=blocked"
    echo "$output" | grep -q "next=v5.3.0"
    echo "$output" | grep -q "latest=v5.2.0"
}
