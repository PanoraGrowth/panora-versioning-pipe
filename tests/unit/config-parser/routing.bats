#!/usr/bin/env bats

# Tests for per-folder changelog routing functions:
# extract_scope_from_commit, find_folder_for_scope

load '../../helpers/setup'
load '../../helpers/assertions'

setup() { common_setup; }
teardown() { common_teardown; }

# =============================================================================
# extract_scope_from_commit
# =============================================================================

@test "extract_scope_from_commit: conventional with scope" {
    source_config_parser "conventional-full"
    run extract_scope_from_commit "feat(cluster-ecs): add new config"
    assert_equals "cluster-ecs" "$output"
}

@test "extract_scope_from_commit: conventional without scope — returns empty" {
    source_config_parser "conventional-full"
    run extract_scope_from_commit "feat: add feature"
    assert_empty "$output"
}

@test "extract_scope_from_commit: scope with multiple words" {
    source_config_parser "conventional-full"
    run extract_scope_from_commit "fix(api-gateway): fix timeout"
    assert_equals "api-gateway" "$output"
}

@test "extract_scope_from_commit: non-conventional message — returns empty" {
    source_config_parser "conventional-full"
    run extract_scope_from_commit "AM-1234 - feat: add feature"
    assert_empty "$output"
}

@test "extract_scope_from_commit: empty message — returns empty" {
    source_config_parser "conventional-full"
    run extract_scope_from_commit ""
    assert_empty "$output"
}

# =============================================================================
# find_folder_for_scope — suffix matching
# =============================================================================

@test "find_folder_for_scope: suffix match — finds numbered subfolder" {
    source_config_parser "monorepo"
    # Create folder structure: services/001-cluster-ecs/
    mkdir -p "${BATS_TEST_TMPDIR}/repo/services/001-cluster-ecs"

    run find_folder_for_scope \
        "cluster-ecs" \
        "services" \
        "^[0-9]{3}-" \
        "suffix"

    assert_equals "${BATS_TEST_TMPDIR}/repo/services/001-cluster-ecs/" "$output"
}

@test "find_folder_for_scope: suffix match — no match returns empty" {
    source_config_parser "monorepo"
    mkdir -p "${BATS_TEST_TMPDIR}/repo/services/001-cluster-ecs"

    run find_folder_for_scope \
        "nonexistent" \
        "services" \
        "^[0-9]{3}-" \
        "suffix"

    assert_empty "$output"
}

@test "find_folder_for_scope: suffix match — skips folders not matching pattern" {
    source_config_parser "monorepo"
    # Create folder that matches scope but NOT the folder_pattern
    mkdir -p "${BATS_TEST_TMPDIR}/repo/services/cluster-ecs"

    run find_folder_for_scope \
        "cluster-ecs" \
        "services" \
        "^[0-9]{3}-" \
        "suffix"

    assert_empty "$output"
}

@test "find_folder_for_scope: suffix match — multiple subfolders, finds correct one" {
    source_config_parser "monorepo"
    mkdir -p "${BATS_TEST_TMPDIR}/repo/services/001-cluster-ecs"
    mkdir -p "${BATS_TEST_TMPDIR}/repo/services/002-cluster-rds"
    mkdir -p "${BATS_TEST_TMPDIR}/repo/services/003-api-gateway"

    run find_folder_for_scope \
        "cluster-rds" \
        "services" \
        "^[0-9]{3}-" \
        "suffix"

    assert_equals "${BATS_TEST_TMPDIR}/repo/services/002-cluster-rds/" "$output"
}

# =============================================================================
# find_folder_for_scope — exact matching
# =============================================================================

@test "find_folder_for_scope: exact match — folder name equals scope" {
    source_config_parser "monorepo"
    mkdir -p "${BATS_TEST_TMPDIR}/repo/services"

    run find_folder_for_scope \
        "services" \
        "services" \
        "" \
        "exact"

    assert_equals "${BATS_TEST_TMPDIR}/repo/services" "$output"
}

@test "find_folder_for_scope: exact match — subfolder discovery" {
    source_config_parser "monorepo"
    mkdir -p "${BATS_TEST_TMPDIR}/repo/services/api-gateway"

    run find_folder_for_scope \
        "api-gateway" \
        "services" \
        "" \
        "exact"

    assert_equals "${BATS_TEST_TMPDIR}/repo/services/api-gateway" "$output"
}

@test "find_folder_for_scope: exact match — no subfolder returns empty" {
    source_config_parser "monorepo"
    mkdir -p "${BATS_TEST_TMPDIR}/repo/services"

    run find_folder_for_scope \
        "nonexistent" \
        "services" \
        "" \
        "exact"

    assert_empty "$output"
}

@test "find_folder_for_scope: empty scope — returns empty" {
    source_config_parser "monorepo"
    mkdir -p "${BATS_TEST_TMPDIR}/repo/services/001-cluster-ecs"

    run find_folder_for_scope \
        "" \
        "services" \
        "^[0-9]{3}-" \
        "suffix"

    assert_empty "$output"
}

@test "find_folder_for_scope: multiple root folders — searches across all" {
    source_config_parser "monorepo"
    mkdir -p "${BATS_TEST_TMPDIR}/repo/services/001-cluster-ecs"
    mkdir -p "${BATS_TEST_TMPDIR}/repo/infrastructure/001-vpc"

    run find_folder_for_scope \
        "vpc" \
        "services infrastructure" \
        "^[0-9]{3}-" \
        "suffix"

    assert_equals "${BATS_TEST_TMPDIR}/repo/infrastructure/001-vpc/" "$output"
}

@test "find_folder_for_scope: nonexistent root folder — skips gracefully" {
    source_config_parser "monorepo"
    # Don't create "services" dir at all

    run find_folder_for_scope \
        "cluster-ecs" \
        "services" \
        "^[0-9]{3}-" \
        "suffix"

    assert_empty "$output"
}

# =============================================================================
# find_folder_for_scope — glob expansion in folders[] (038)
# =============================================================================

@test "find_folder_for_scope: glob pattern expands and matches subfolder" {
    source_config_parser "monorepo-glob-folders"
    mkdir -p "${BATS_TEST_TMPDIR}/repo/shared/utils"
    mkdir -p "${BATS_TEST_TMPDIR}/repo/shared/lib"

    run find_folder_for_scope \
        "utils" \
        "shared/*" \
        "" \
        "exact"

    assert_equals "${BATS_TEST_TMPDIR}/repo/shared/utils" "$output"
}

@test "find_folder_for_scope: glob pattern — nonexistent parent does not error" {
    source_config_parser "monorepo-glob-folders"
    # shared/ does not exist at all

    run find_folder_for_scope \
        "utils" \
        "shared/*" \
        "" \
        "exact"

    assert_empty "$output"
}

# =============================================================================
# find_folder_for_scope — multi-level suffix matching (036)
# =============================================================================

@test "find_folder_for_scope: suffix match — finds subfolder 2 levels deep" {
    source_config_parser "monorepo"
    # 2 levels deep: services/003-api-gateway/001-routes/
    mkdir -p "${BATS_TEST_TMPDIR}/repo/services/003-api-gateway/001-routes"

    run find_folder_for_scope \
        "routes" \
        "services" \
        "^[0-9]{3}-" \
        "suffix"

    assert_equals "${BATS_TEST_TMPDIR}/repo/services/003-api-gateway/001-routes/" "$output"
}

@test "find_folder_for_scope: suffix match — does not find folder beyond default depth" {
    source_config_parser "monorepo"
    # depth=2 by default; level 3 (inside services/l1/l2/) should not be reached
    mkdir -p "${BATS_TEST_TMPDIR}/repo/services/001-level1/002-level2/003-routes"

    run find_folder_for_scope \
        "routes" \
        "services" \
        "^[0-9]{3}-" \
        "suffix"

    assert_empty "$output"
}
