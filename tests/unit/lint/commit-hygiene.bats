#!/usr/bin/env bats

# Tests for scripts/lint/check-commit-hygiene.sh
#
# The script is copied into the Docker image at /pipe/lint/check-commit-hygiene.sh
# (Dockerfile: COPY scripts/ /pipe/). All tests invoke it as a subprocess via
# `run` and assert exit status + stderr/stdout content.

load '../../helpers/setup'
load '../../helpers/assertions'

LINT_SCRIPT="/pipe/lint/check-commit-hygiene.sh"

setup() { common_setup; }
teardown() { common_teardown; }

# =============================================================================
# Clean messages — must pass
# =============================================================================

@test "clean subject-only message exits 0" {
    run "$LINT_SCRIPT" -m "feat: add new feature"
    [ "$status" -eq 0 ]
}

@test "clean multi-line message exits 0" {
    run "$LINT_SCRIPT" -m "$(printf 'feat: add new feature\n\nLonger body describing the change.\n')"
    [ "$status" -eq 0 ]
}

@test "safe alternative 'skip-ci' (with dash) exits 0" {
    run "$LINT_SCRIPT" -m "docs: explain the skip-ci behavior of the pipe"
    [ "$status" -eq 0 ]
}

@test "safe alternative 'the CI skip directive' exits 0" {
    run "$LINT_SCRIPT" -m "docs: mention the CI skip directive in CONTRIBUTING"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Each of the 6 forbidden variants — must fail
# =============================================================================

@test "subject with [skip ci] exits 1" {
    run "$LINT_SCRIPT" -m "feat: something [skip ci]"
    [ "$status" -eq 1 ]
    [[ "$output" == *"forbidden substring: [skip ci]"* ]]
}

@test "body with [skip ci] as prose exits 1" {
    run "$LINT_SCRIPT" -m "$(printf 'feat: add docs\n\nExplain how the [skip ci] atomic push works.\n')"
    [ "$status" -eq 1 ]
    [[ "$output" == *"forbidden substring: [skip ci]"* ]]
}

@test "body with [ci skip] exits 1" {
    run "$LINT_SCRIPT" -m "$(printf 'feat: foo\n\nSome [ci skip] prose.\n')"
    [ "$status" -eq 1 ]
    [[ "$output" == *"forbidden substring: [ci skip]"* ]]
}

@test "body with [no ci] exits 1" {
    run "$LINT_SCRIPT" -m "$(printf 'feat: foo\n\nSome [no ci] prose.\n')"
    [ "$status" -eq 1 ]
    [[ "$output" == *"forbidden substring: [no ci]"* ]]
}

@test "body with [skip actions] exits 1" {
    run "$LINT_SCRIPT" -m "$(printf 'feat: foo\n\nSome [skip actions] prose.\n')"
    [ "$status" -eq 1 ]
    [[ "$output" == *"forbidden substring: [skip actions]"* ]]
}

@test "body with [actions skip] exits 1" {
    run "$LINT_SCRIPT" -m "$(printf 'feat: foo\n\nSome [actions skip] prose.\n')"
    [ "$status" -eq 1 ]
    [[ "$output" == *"forbidden substring: [actions skip]"* ]]
}

@test "body with 'skip-checks: true' trailer exits 1" {
    run "$LINT_SCRIPT" -m "$(printf 'feat: foo\n\nskip-checks: true\n')"
    [ "$status" -eq 1 ]
    [[ "$output" == *"forbidden substring: skip-checks: true"* ]]
}

# =============================================================================
# Case-insensitive — must also fail
# =============================================================================

@test "mixed-case [Skip CI] exits 1" {
    run "$LINT_SCRIPT" -m "feat: foo [Skip CI]"
    [ "$status" -eq 1 ]
}

@test "upper-case [SKIP CI] exits 1" {
    run "$LINT_SCRIPT" -m "feat: foo [SKIP CI]"
    [ "$status" -eq 1 ]
}

@test "mixed-case [Ci Skip] exits 1" {
    run "$LINT_SCRIPT" -m "feat: foo [Ci Skip]"
    [ "$status" -eq 1 ]
}

# =============================================================================
# Exemption trailer — must pass
# =============================================================================

@test "forbidden substring + X-Intentional-Skip-CI trailer exits 0" {
    run "$LINT_SCRIPT" -m "$(printf 'docs: pure docs, no code touched\n\nX-Intentional-Skip-CI: true\n[skip ci]\n')"
    [ "$status" -eq 0 ]
}

@test "exemption trailer alone (no forbidden substring) exits 0" {
    run "$LINT_SCRIPT" -m "$(printf 'docs: pure docs\n\nX-Intentional-Skip-CI: true\n')"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Pipe-authored allowlist — must pass
# =============================================================================

@test "chore(release) subject with [skip ci] exits 0" {
    run "$LINT_SCRIPT" -m "chore(release): update CHANGELOG for version v1.0.0 (minor bump) [skip ci]"
    [ "$status" -eq 0 ]
}

@test "chore(hotfix) subject with [skip ci] exits 0" {
    run "$LINT_SCRIPT" -m "chore(hotfix): update CHANGELOG for main hotfix [skip ci]"
    [ "$status" -eq 0 ]
}

@test "chore(release) without forbidden substring still exits 0" {
    run "$LINT_SCRIPT" -m "chore(release): update CHANGELOG for version v1.0.0"
    [ "$status" -eq 0 ]
}

# =============================================================================
# -f mode (file input)
# =============================================================================

@test "-f mode: clean file exits 0" {
    local msg_file="${BATS_TEST_TMPDIR}/msg"
    printf 'feat: clean message\n' > "$msg_file"
    run "$LINT_SCRIPT" -f "$msg_file"
    [ "$status" -eq 0 ]
}

@test "-f mode: dirty file exits 1" {
    local msg_file="${BATS_TEST_TMPDIR}/msg"
    printf 'feat: bad message [skip ci]\n' > "$msg_file"
    run "$LINT_SCRIPT" -f "$msg_file"
    [ "$status" -eq 1 ]
    [[ "$output" == *"forbidden substring: [skip ci]"* ]]
}

@test "-f mode: missing file exits 2" {
    run "$LINT_SCRIPT" -f "${BATS_TEST_TMPDIR}/does-not-exist"
    [ "$status" -eq 2 ]
    [[ "$output" == *"cannot read file"* ]]
}

# =============================================================================
# Usage errors
# =============================================================================

@test "no arguments prints usage and exits 2" {
    run "$LINT_SCRIPT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "unknown flag exits 2" {
    run "$LINT_SCRIPT" -z foo
    [ "$status" -eq 2 ]
}

@test "-h prints usage and exits 0" {
    run "$LINT_SCRIPT" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

# =============================================================================
# Error output includes a pointer to CONTRIBUTING.md
# =============================================================================

@test "dirty message error references CONTRIBUTING.md" {
    run "$LINT_SCRIPT" -m "feat: foo [skip ci]"
    [ "$status" -eq 1 ]
    [[ "$output" == *"CONTRIBUTING.md"* ]]
}

@test "dirty message error suggests safe alternatives" {
    run "$LINT_SCRIPT" -m "feat: foo [skip ci]"
    [ "$status" -eq 1 ]
    [[ "$output" == *"skip-ci"* ]]
}
