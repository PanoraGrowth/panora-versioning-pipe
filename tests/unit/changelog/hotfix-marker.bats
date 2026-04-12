#!/usr/bin/env bats

# hotfix-marker.bats — tests for the "(Hotfix)" CHANGELOG header marker.
#
# Both generate-changelog-last-commit.sh (root) and generate-changelog-per-folder.sh
# (subfolders) must inject " (Hotfix)" into the version header when the scenario
# is hotfix. Development releases render unchanged.

load '../../helpers/setup'
load '../../helpers/assertions'

LOCKFILE="/tmp/.versioning-merged.lock"

setup() { common_setup; }

teardown() {
    common_teardown
    rm -f /tmp/scenario.env /tmp/.versioning-merged.yml \
          /tmp/next_version.txt /tmp/routed_commits.txt \
          /tmp/per_folder_changelogs.txt
}

# Run generate-changelog-last-commit.sh with the given scenario against a
# fixture + seeded commit. Captures the final CHANGELOG header line via the
# same flock the other subprocess tests use.
run_root_generator() {
    local fixture="$1"
    local scenario="$2"

    cp "${PIPE_DIR}/tests/fixtures/${fixture}.yml" \
       "${BATS_TEST_TMPDIR}/repo/.versioning.yml"

    cd "${BATS_TEST_TMPDIR}/repo" || return 1

    echo "artifact" > artifact.txt
    git add artifact.txt .versioning.yml >/dev/null
    git commit -q -m "feat: hotfix header marker probe"

    echo "SCENARIO=${scenario}" > /tmp/scenario.env
    echo "v0.5.9" > /tmp/next_version.txt

    run flock "$LOCKFILE" sh -c "
        cd '${BATS_TEST_TMPDIR}/repo' && \
        sh '${PIPE_DIR}/changelog/generate-changelog-last-commit.sh' >/dev/null 2>&1 ; \
        head -20 CHANGELOG.md 2>/dev/null || true
    "
}

# =============================================================================
# Root CHANGELOG header marker
# =============================================================================

@test "hotfix scenario: root CHANGELOG header includes ' (Hotfix)' marker" {
    run_root_generator "minimal" "hotfix"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qE '^## v0\.5\.9 \(Hotfix\) - [0-9]{4}-[0-9]{2}-[0-9]{2}$'
}

@test "development_release: root CHANGELOG header does NOT include '(Hotfix)'" {
    run_root_generator "minimal" "development_release"
    [ "$status" -eq 0 ]
    # Header must be the bare version — no marker
    echo "$output" | grep -qE '^## v0\.5\.9 - [0-9]{4}-[0-9]{2}-[0-9]{2}$'
    # And must NOT contain the marker anywhere in the first 20 lines
    ! echo "$output" | grep -q '(Hotfix)'
}

# =============================================================================
# Per-folder CHANGELOG header marker — consistency check
# =============================================================================

@test "hotfix scenario: per-folder generator applies marker consistently" {
    # Use a minimal inline fixture with per_folder enabled and a subfolder
    cat > "${BATS_TEST_TMPDIR}/repo/.versioning.yml" <<'EOF'
commits:
  format: "conventional"
version:
  components:
    major:
      enabled: true
      initial: 0
    minor:
      enabled: true
      initial: 0
    timestamp:
      enabled: false
changelog:
  per_folder:
    enabled: true
    folders: ["backend"]
    scope_matching: "exact"
    fallback: "root"
EOF

    cd "${BATS_TEST_TMPDIR}/repo" || return 1
    mkdir -p backend
    echo "art" > backend/file.txt
    git add backend/ .versioning.yml >/dev/null
    git commit -q -m "feat(backend): hotfix marker test"

    echo "SCENARIO=hotfix" > /tmp/scenario.env
    echo "v0.5.9" > /tmp/next_version.txt

    run flock "$LOCKFILE" sh -c "
        cd '${BATS_TEST_TMPDIR}/repo' && \
        sh '${PIPE_DIR}/changelog/generate-changelog-per-folder.sh' >/dev/null 2>&1 ; \
        head -20 backend/CHANGELOG.md 2>/dev/null || true
    "
    [ "$status" -eq 0 ]
    echo "$output" | grep -qE '^## v0\.5\.9 \(Hotfix\) - [0-9]{4}-[0-9]{2}-[0-9]{2}$'
}
