#!/usr/bin/env bats

# Tests for pipe.sh platform detection — runs as subprocess
# Mocks configure-git.sh to avoid real git config operations

load '../../helpers/setup'
load '../../helpers/assertions'

PIPE_SCRIPT="/pipe/pipe.sh"

setup() {
    common_setup

    # Mock configure-git.sh — pipe.sh calls it before platform detection
    mkdir -p "${BATS_TEST_TMPDIR}/mock-pipe/setup"
    cp "$PIPE_SCRIPT" "${BATS_TEST_TMPDIR}/mock-pipe.sh"

    # Replace /pipe with our mock dir in the copied script
    sed -i "s|SCRIPTS_DIR=\"/pipe\"|SCRIPTS_DIR=\"${BATS_TEST_TMPDIR}/mock-pipe\"|" \
        "${BATS_TEST_TMPDIR}/mock-pipe.sh"

    # Create no-op configure-git.sh
    cat > "${BATS_TEST_TMPDIR}/mock-pipe/setup/configure-git.sh" <<'MOCK'
#!/bin/sh
# no-op mock
MOCK
    chmod +x "${BATS_TEST_TMPDIR}/mock-pipe/setup/configure-git.sh"

    # Create no-op orchestration scripts so pipe.sh doesn't fail
    mkdir -p "${BATS_TEST_TMPDIR}/mock-pipe/orchestration"
    cat > "${BATS_TEST_TMPDIR}/mock-pipe/orchestration/pr-pipeline.sh" <<'MOCK'
#!/bin/sh
echo "PR pipeline mock"
MOCK
    cat > "${BATS_TEST_TMPDIR}/mock-pipe/orchestration/branch-pipeline.sh" <<'MOCK'
#!/bin/sh
echo "Branch pipeline mock"
MOCK
    chmod +x "${BATS_TEST_TMPDIR}/mock-pipe/orchestration/pr-pipeline.sh"
    chmod +x "${BATS_TEST_TMPDIR}/mock-pipe/orchestration/branch-pipeline.sh"

    cd "${BATS_TEST_TMPDIR}/repo" || return 1
}

teardown() { common_teardown; }

# --- Bitbucket Pipelines ---

@test "platform: Bitbucket — maps BITBUCKET_* to VERSIONING_*" {
    run env -i HOME="$HOME" PATH="$PATH" \
        BITBUCKET_BUILD_NUMBER="42" \
        BITBUCKET_PR_ID="99" \
        BITBUCKET_BRANCH="feature/test" \
        BITBUCKET_PR_DESTINATION_BRANCH="main" \
        BITBUCKET_COMMIT="abc123" \
        bash "${BATS_TEST_TMPDIR}/mock-pipe.sh"

    [ "$status" -eq 0 ]
    assert_output_matches "Platform detected: Bitbucket Pipelines"
    assert_output_matches "PR PIPELINE"
}

@test "platform: Bitbucket — VERSIONING_* takes priority over BITBUCKET_*" {
    run env -i HOME="$HOME" PATH="$PATH" \
        BITBUCKET_BUILD_NUMBER="42" \
        BITBUCKET_BRANCH="wrong-branch" \
        VERSIONING_BRANCH="correct-branch" \
        bash "${BATS_TEST_TMPDIR}/mock-pipe.sh"

    [ "$status" -eq 0 ]
    assert_output_matches "Bitbucket Pipelines"
    assert_output_matches "BRANCH PIPELINE"
}

# --- GitHub Actions ---

@test "platform: GitHub Actions PR — maps GITHUB_* to VERSIONING_*" {
    # Create mock event payload
    local event_file="${BATS_TEST_TMPDIR}/event.json"
    echo '{"pull_request":{"number":55}}' > "$event_file"

    run env -i HOME="$HOME" PATH="$PATH" \
        GITHUB_ACTIONS="true" \
        GITHUB_EVENT_NAME="pull_request" \
        GITHUB_EVENT_PATH="$event_file" \
        GITHUB_HEAD_REF="feature/gh-test" \
        GITHUB_BASE_REF="main" \
        GITHUB_SHA="def456" \
        bash "${BATS_TEST_TMPDIR}/mock-pipe.sh"

    [ "$status" -eq 0 ]
    assert_output_matches "Platform detected: GitHub Actions"
    assert_output_matches "PR PIPELINE"
}

@test "platform: GitHub Actions push — maps GITHUB_REF_NAME to VERSIONING_BRANCH" {
    run env -i HOME="$HOME" PATH="$PATH" \
        GITHUB_ACTIONS="true" \
        GITHUB_EVENT_NAME="push" \
        GITHUB_REF_NAME="main" \
        GITHUB_SHA="def456" \
        bash "${BATS_TEST_TMPDIR}/mock-pipe.sh"

    [ "$status" -eq 0 ]
    assert_output_matches "GitHub Actions"
    assert_output_matches "BRANCH PIPELINE"
}

# --- Generic CI ---

@test "platform: Generic CI — uses VERSIONING_* directly" {
    run env -i HOME="$HOME" PATH="$PATH" \
        VERSIONING_BRANCH="main" \
        VERSIONING_COMMIT="aaa111" \
        bash "${BATS_TEST_TMPDIR}/mock-pipe.sh"

    [ "$status" -eq 0 ]
    assert_output_matches "Generic CI"
    assert_output_matches "BRANCH PIPELINE"
}

@test "platform: no vars set — exits with error" {
    run env -i HOME="$HOME" PATH="$PATH" \
        bash "${BATS_TEST_TMPDIR}/mock-pipe.sh"

    [ "$status" -eq 1 ]
    assert_output_matches "Cannot determine pipeline type"
}
