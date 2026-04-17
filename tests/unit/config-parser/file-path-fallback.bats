#!/usr/bin/env bats

# Tests for find_folder_by_file_path() — the fallback: "file_path" routing path.
# This function resolves a commit to a folder by checking which configured folder
# contains the modified files. Returns a folder path when all changed files fall
# within exactly ONE configured folder, empty otherwise.

load '../../helpers/setup'
load '../../helpers/assertions'

setup() { common_setup; }
teardown() { common_teardown; }

# Helper: create a commit that touches the given file paths.
# Usage: create_commit_with_files "api/main.go" "api/handler.go"
# Returns: the commit hash via stdout
create_commit_with_files() {
    local repo="${BATS_TEST_TMPDIR}/repo"
    for f in "$@"; do
        mkdir -p "${repo}/$(dirname "$f")"
        echo "content" > "${repo}/${f}"
        git -C "$repo" add "$f"
    done
    git -C "$repo" commit -q -m "test commit"
    git -C "$repo" rev-parse HEAD
}

# =============================================================================
# find_folder_by_file_path
# =============================================================================

@test "find_folder_by_file_path: returns matching folder when file is inside a configured folder" {
    source_config_parser "monorepo-file-path-fallback"
    local hash=$(create_commit_with_files "api/main.go")

    run find_folder_by_file_path "$hash" "api web shared"
    assert_equals "${BATS_TEST_TMPDIR}/repo/api" "$output"
}

@test "find_folder_by_file_path: returns matching folder with multiple files in same folder" {
    source_config_parser "monorepo-file-path-fallback"
    local hash=$(create_commit_with_files "web/index.html" "web/style.css")

    run find_folder_by_file_path "$hash" "api web shared"
    assert_equals "${BATS_TEST_TMPDIR}/repo/web" "$output"
}

@test "find_folder_by_file_path: returns empty when no folder matches" {
    source_config_parser "monorepo-file-path-fallback"
    local hash=$(create_commit_with_files "docs/readme.md")

    run find_folder_by_file_path "$hash" "api web shared"
    assert_empty "$output"
}

@test "find_folder_by_file_path: returns all matched folders when files span multiple folders" {
    source_config_parser "monorepo-file-path-fallback"
    local hash=$(create_commit_with_files "api/main.go" "web/index.html")

    run find_folder_by_file_path "$hash" "api web shared"
    assert_line_count 2
    assert_line "${BATS_TEST_TMPDIR}/repo/api"
    assert_line "${BATS_TEST_TMPDIR}/repo/web"
}

@test "find_folder_by_file_path: handles nested files within a folder correctly" {
    source_config_parser "monorepo-file-path-fallback"
    local hash=$(create_commit_with_files "shared/utils/helpers.sh" "shared/lib/core.sh")

    run find_folder_by_file_path "$hash" "api web shared"
    assert_equals "${BATS_TEST_TMPDIR}/repo/shared" "$output"
}

@test "find_folder_by_file_path: files at root (outside any folder) — returns empty" {
    source_config_parser "monorepo-file-path-fallback"
    local hash=$(create_commit_with_files "README.md")

    run find_folder_by_file_path "$hash" "api web shared"
    assert_empty "$output"
}

@test "find_folder_by_file_path: returns all three folders when files span three configured folders" {
    source_config_parser "monorepo-file-path-fallback"
    local hash=$(create_commit_with_files "api/main.go" "web/index.html" "shared/utils/helpers.sh")

    run find_folder_by_file_path "$hash" "api web shared"
    assert_line_count 3
    assert_line "${BATS_TEST_TMPDIR}/repo/api"
    assert_line "${BATS_TEST_TMPDIR}/repo/web"
    assert_line "${BATS_TEST_TMPDIR}/repo/shared"
}

@test "find_folder_by_file_path: mixed root and folder files — unmatched root files are ignored" {
    source_config_parser "monorepo-file-path-fallback"
    local hash=$(create_commit_with_files "api/main.go" "README.md")

    # README.md doesn't match any configured folder, so it's silently ignored.
    # Only api/main.go sets _matched="api". Result: api folder is returned.
    run find_folder_by_file_path "$hash" "api web shared"
    assert_equals "${BATS_TEST_TMPDIR}/repo/api" "$output"
}
