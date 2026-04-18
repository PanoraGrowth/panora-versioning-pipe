#!/usr/bin/env bats

# write-version-file-extended.bats — additional coverage for write-version-file.sh
#
# Covers: yaml/json creation when file does not exist, path glob expansion with matches,
# trigger_paths matching/non-matching, multiple groups isolation.
#
# trigger_paths tests require a local git remote so get_changed_files() returns
# the right diff. We create a bare repo as origin and push a base commit, then
# add changes on top so git diff origin/main...HEAD shows the right files.

load '../../helpers/setup'
load '../../helpers/assertions'

LOCKFILE="/tmp/.versioning-merged.lock"

setup() { common_setup; }

teardown() {
    common_teardown
    rm -f /tmp/next_version.txt /tmp/.versioning-merged.yml \
          /tmp/version_files_modified.txt /tmp/bump_type.txt
}

run_write_version_file() {
    local version="$1"
    run flock "$LOCKFILE" sh -c "
        echo '${version}' > /tmp/next_version.txt ; \
        cd '${BATS_TEST_TMPDIR}/repo' && \
        sh '${PIPE_DIR}/versioning/write-version-file.sh' 2>&1
    "
}

run_write_version_file_with_target() {
    local version="$1"
    local target_branch="$2"
    run flock "$LOCKFILE" sh -c "
        echo '${version}' > /tmp/next_version.txt ; \
        export VERSIONING_TARGET_BRANCH='${target_branch}' ; \
        cd '${BATS_TEST_TMPDIR}/repo' && \
        sh '${PIPE_DIR}/versioning/write-version-file.sh' 2>&1
    "
}

# Set up a local bare remote so git diff origin/... works in unit tests.
# Creates: ${BATS_TEST_TMPDIR}/remote.git (bare) → pushed as origin with 1 base commit.
# After setup, the caller adds files and commits to simulate PR changes.
setup_local_remote() {
    local base_branch="${1:-main}"

    # Create bare remote
    git init --bare -q "${BATS_TEST_TMPDIR}/remote.git"

    # Add as origin and push initial state
    git -C "${BATS_TEST_TMPDIR}/repo" remote add origin "${BATS_TEST_TMPDIR}/remote.git"
    git -C "${BATS_TEST_TMPDIR}/repo" push -q origin HEAD:refs/heads/"${base_branch}"
}

read_yaml_key() {
    local file="$1"
    local key="$2"
    yq -r ".${key}" "$file"
}

read_json_key() {
    local file="$1"
    local key="$2"
    yq -r -p=json ".${key}" "$file"
}

# =============================================================================
# yaml/json — file does not exist (creation)
# =============================================================================

@test "yaml: creates file with version when file does not exist" {
    write_inline_fixture '
commits:
  format: "conventional"
version:
  tag_prefix_v: false
  components:
    major: { enabled: true, initial: 0 }
    patch: { enabled: true, initial: 0 }
version_file:
  enabled: true
  groups:
    - name: "root"
      files:
        - path: "newdir/version.yaml"
'
    run_write_version_file "2.3.0"
    [ "$status" -eq 0 ]
    actual=$(read_yaml_key "${BATS_TEST_TMPDIR}/repo/newdir/version.yaml" "version")
    assert_equals "2.3.0" "$actual"
}

@test "json: creates file with version when file does not exist" {
    write_inline_fixture '
commits:
  format: "conventional"
version:
  tag_prefix_v: false
  components:
    major: { enabled: true, initial: 0 }
    patch: { enabled: true, initial: 0 }
version_file:
  enabled: true
  groups:
    - name: "root"
      files:
        - path: "newpkg/package.json"
'
    run_write_version_file "3.0.0"
    [ "$status" -eq 0 ]
    actual=$(read_json_key "${BATS_TEST_TMPDIR}/repo/newpkg/package.json" "version")
    assert_equals "3.0.0" "$actual"
}

# =============================================================================
# Path glob — expansion with matches
# =============================================================================

@test "path glob with matches: expands and updates all matching files" {
    write_inline_fixture '
commits:
  format: "conventional"
version:
  tag_prefix_v: false
  components:
    major: { enabled: true, initial: 0 }
    patch: { enabled: true, initial: 0 }
version_file:
  enabled: true
  groups:
    - name: "packages"
      files:
        - path: "packages/version.yaml"
'
    mkdir -p "${BATS_TEST_TMPDIR}/repo/packages"
    echo "version: \"0.0.0\"" > "${BATS_TEST_TMPDIR}/repo/packages/version.yaml"

    run_write_version_file "1.7.0"
    [ "$status" -eq 0 ]

    actual=$(read_yaml_key "${BATS_TEST_TMPDIR}/repo/packages/version.yaml" "version")
    assert_equals "1.7.0" "$actual"
}

# =============================================================================
# trigger_paths — matching and non-matching (requires local remote)
# =============================================================================

@test "trigger_paths: group with matching path is updated" {
    write_inline_fixture '
commits:
  format: "conventional"
version:
  tag_prefix_v: false
  components:
    major: { enabled: true, initial: 0 }
    patch: { enabled: true, initial: 0 }
version_file:
  enabled: true
  groups:
    - name: "frontend"
      trigger_paths:
        - "packages/frontend/**"
      files:
        - path: "packages/frontend/version.yaml"
'
    setup_local_remote "main"

    # Create a changed file under packages/frontend/ (simulates PR change)
    mkdir -p "${BATS_TEST_TMPDIR}/repo/packages/frontend"
    echo "version: \"0.0.0\"" > "${BATS_TEST_TMPDIR}/repo/packages/frontend/version.yaml"
    echo "changed" > "${BATS_TEST_TMPDIR}/repo/packages/frontend/app.ts"
    git -C "${BATS_TEST_TMPDIR}/repo" add packages/
    git -C "${BATS_TEST_TMPDIR}/repo" commit -q -m "feat: frontend changes"

    run_write_version_file_with_target "1.2.0" "main"
    [ "$status" -eq 0 ]

    actual=$(read_yaml_key "${BATS_TEST_TMPDIR}/repo/packages/frontend/version.yaml" "version")
    assert_equals "1.2.0" "$actual"
}

@test "trigger_paths: group with non-matching path is skipped" {
    write_inline_fixture '
commits:
  format: "conventional"
version:
  tag_prefix_v: false
  components:
    major: { enabled: true, initial: 0 }
    patch: { enabled: true, initial: 0 }
version_file:
  enabled: true
  groups:
    - name: "backend"
      trigger_paths:
        - "packages/backend/**"
      files:
        - path: "packages/backend/version.yaml"
'
    setup_local_remote "main"

    # Create the version file but only commit frontend changes (no backend changes)
    mkdir -p "${BATS_TEST_TMPDIR}/repo/packages/backend"
    echo "version: \"0.0.0\"" > "${BATS_TEST_TMPDIR}/repo/packages/backend/version.yaml"
    git -C "${BATS_TEST_TMPDIR}/repo" add packages/
    git -C "${BATS_TEST_TMPDIR}/repo" commit -q -m "chore: commit base files"
    git -C "${BATS_TEST_TMPDIR}/repo" push -q origin HEAD:refs/heads/main

    # Now make a change that does NOT touch packages/backend/
    echo "changed" > "${BATS_TEST_TMPDIR}/repo/other.txt"
    git -C "${BATS_TEST_TMPDIR}/repo" add other.txt
    git -C "${BATS_TEST_TMPDIR}/repo" commit -q -m "docs: update readme"

    run_write_version_file_with_target "1.2.0" "main"
    [ "$status" -eq 0 ]

    # version.yaml should be unchanged (still 0.0.0)
    actual=$(read_yaml_key "${BATS_TEST_TMPDIR}/repo/packages/backend/version.yaml" "version")
    assert_equals "0.0.0" "$actual"
    [[ "$output" == *"trigger_paths did not match"* ]]
}

@test "trigger_paths: branch pipeline (no VERSIONING_TARGET_BRANCH) uses HEAD diff-tree and matches" {
    write_inline_fixture '
commits:
  format: "conventional"
version:
  tag_prefix_v: false
  components:
    major: { enabled: true, initial: 0 }
    patch: { enabled: true, initial: 0 }
version_file:
  enabled: true
  groups:
    - name: "services"
      trigger_paths:
        - "services/**"
      files:
        - path: "services/version.yaml"
'
    # Simulate branch pipeline post-merge: no origin remote, no
    # VERSIONING_TARGET_BRANCH. HEAD is the merge commit and its changed
    # files must be visible via git diff-tree -r HEAD.
    mkdir -p "${BATS_TEST_TMPDIR}/repo/services"
    echo "version: \"0.0.0\"" > "${BATS_TEST_TMPDIR}/repo/services/version.yaml"
    git -C "${BATS_TEST_TMPDIR}/repo" add services/
    git -C "${BATS_TEST_TMPDIR}/repo" commit -q -m "chore: base commit"

    echo "# new services layer" > "${BATS_TEST_TMPDIR}/repo/services/main.tf"
    git -C "${BATS_TEST_TMPDIR}/repo" add services/main.tf
    git -C "${BATS_TEST_TMPDIR}/repo" commit -q -m "feat: deploy new services layer"

    run_write_version_file "19.1.0"
    [ "$status" -eq 0 ]

    actual=$(read_yaml_key "${BATS_TEST_TMPDIR}/repo/services/version.yaml" "version")
    assert_equals "19.1.0" "$actual"
}

@test "trigger_paths: branch pipeline (no VERSIONING_TARGET_BRANCH) uses HEAD diff-tree and skips on no-match" {
    write_inline_fixture '
commits:
  format: "conventional"
version:
  tag_prefix_v: false
  components:
    major: { enabled: true, initial: 0 }
    patch: { enabled: true, initial: 0 }
version_file:
  enabled: true
  groups:
    - name: "services"
      trigger_paths:
        - "services/**"
      files:
        - path: "services/version.yaml"
'
    mkdir -p "${BATS_TEST_TMPDIR}/repo/services"
    mkdir -p "${BATS_TEST_TMPDIR}/repo/infrastructure"
    echo "version: \"0.0.0\"" > "${BATS_TEST_TMPDIR}/repo/services/version.yaml"
    git -C "${BATS_TEST_TMPDIR}/repo" add services/
    git -C "${BATS_TEST_TMPDIR}/repo" commit -q -m "chore: base commit"

    echo "# docs" > "${BATS_TEST_TMPDIR}/repo/infrastructure/README.md"
    git -C "${BATS_TEST_TMPDIR}/repo" add infrastructure/README.md
    git -C "${BATS_TEST_TMPDIR}/repo" commit -q -m "feat: update infrastructure docs"

    run_write_version_file "20.1.0"
    [ "$status" -eq 0 ]

    actual=$(read_yaml_key "${BATS_TEST_TMPDIR}/repo/services/version.yaml" "version")
    assert_equals "0.0.0" "$actual"
    [[ "$output" == *"trigger_paths did not match"* ]]
}

@test "multiple groups: only matching trigger_paths group is updated" {
    write_inline_fixture '
commits:
  format: "conventional"
version:
  tag_prefix_v: false
  components:
    major: { enabled: true, initial: 0 }
    patch: { enabled: true, initial: 0 }
version_file:
  enabled: true
  groups:
    - name: "frontend"
      trigger_paths:
        - "packages/frontend/**"
      files:
        - path: "packages/frontend/version.yaml"
    - name: "backend"
      trigger_paths:
        - "packages/backend/**"
      files:
        - path: "packages/backend/version.yaml"
'
    setup_local_remote "main"

    # Create both version files as base state on origin
    mkdir -p "${BATS_TEST_TMPDIR}/repo/packages/frontend"
    mkdir -p "${BATS_TEST_TMPDIR}/repo/packages/backend"
    echo "version: \"0.0.0\"" > "${BATS_TEST_TMPDIR}/repo/packages/frontend/version.yaml"
    echo "version: \"0.0.0\"" > "${BATS_TEST_TMPDIR}/repo/packages/backend/version.yaml"
    git -C "${BATS_TEST_TMPDIR}/repo" add packages/
    git -C "${BATS_TEST_TMPDIR}/repo" commit -q -m "chore: add version files"
    git -C "${BATS_TEST_TMPDIR}/repo" push -q origin HEAD:refs/heads/main

    # Add a change only in frontend
    echo "changed" > "${BATS_TEST_TMPDIR}/repo/packages/frontend/app.ts"
    git -C "${BATS_TEST_TMPDIR}/repo" add packages/frontend/app.ts
    git -C "${BATS_TEST_TMPDIR}/repo" commit -q -m "feat: frontend feature"

    run_write_version_file_with_target "2.0.0" "main"
    [ "$status" -eq 0 ]

    # Frontend updated, backend unchanged
    frontend=$(read_yaml_key "${BATS_TEST_TMPDIR}/repo/packages/frontend/version.yaml" "version")
    backend=$(read_yaml_key "${BATS_TEST_TMPDIR}/repo/packages/backend/version.yaml" "version")
    assert_equals "2.0.0" "$frontend"
    assert_equals "0.0.0" "$backend"
}
