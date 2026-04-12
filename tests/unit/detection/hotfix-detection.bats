#!/usr/bin/env bats

# hotfix-detection.bats — branch-context hotfix detection via commit subject
# convention. Platform-agnostic, no mocks, no API calls.
#
# Exercises the v0.6.3 detection model:
#   - Primary: HEAD commit subject matches "{keyword}:*" or "{keyword}(*"
#   - Secondary: for merge-commit style, HEAD is a merge commit and its second
#     parent's subject matches
#   - Keyword is config-driven via hotfix.keyword
#   - Strict prefix match (no false positives on "hotfixed", "pre-hotfix", etc.)
#   - Custom keyword isolation (consumer with keyword "urgent" does not match
#     "hotfix:", and vice versa)

load '../../helpers/setup'
load '../../helpers/assertions'

LOCKFILE="/tmp/.versioning-merged.lock"

setup() { common_setup; }

teardown() {
    common_teardown
    rm -f /tmp/scenario.env /tmp/.versioning-merged.yml
}

# Run detect-scenario.sh in branch context (no target branch) against a fixture
# with an already-committed HEAD. Captures SCENARIO from /tmp/scenario.env.
#
# Usage: run_detect "<fixture>"
run_detect() {
    local fixture="$1"

    cp "${PIPE_DIR}/tests/fixtures/${fixture}.yml" \
       "${BATS_TEST_TMPDIR}/repo/.versioning.yml"

    cd "${BATS_TEST_TMPDIR}/repo" || return 1

    run flock "$LOCKFILE" sh -c "
        cd '${BATS_TEST_TMPDIR}/repo' && \
        sh '${PIPE_DIR}/detection/detect-scenario.sh' >/dev/null 2>&1 ; \
        cat /tmp/scenario.env 2>/dev/null
    "
}

# Create a single commit on the current branch with the given subject.
seed_head_commit() {
    local subject="$1"
    cd "${BATS_TEST_TMPDIR}/repo" || return 1
    echo "artifact-$RANDOM" > "artifact-$RANDOM.txt"
    git add -A >/dev/null
    git commit -q -m "$subject"
}

# Create a merge commit by merging an orphan branch into main with its branch
# tip carrying the given subject. Simulates the "merge commit" (not squash/rebase)
# merge style. Uses --no-ff to guarantee a merge commit even if fast-forward is
# possible.
seed_merge_commit_with_branch_tip() {
    local branch_subject="$1"
    cd "${BATS_TEST_TMPDIR}/repo" || return 1

    # Ensure we're on main with an initial commit (from common_setup)
    git checkout -q -b hotfix-branch-tip
    echo "branch-artifact" > branch-file.txt
    git add branch-file.txt >/dev/null
    git commit -q -m "$branch_subject"

    git checkout -q main 2>/dev/null || git checkout -q master 2>/dev/null || \
        git checkout -q -b main
    git merge -q --no-ff hotfix-branch-tip -m "Merge pull request #42 from agustin/hotfix-branch-tip" >/dev/null
}

# =============================================================================
# Bloque 1 — Pattern matching puro con keyword default "hotfix"
# =============================================================================

@test "default keyword: subject 'hotfix: foo' → scenario=hotfix" {
    seed_head_commit "hotfix: fix auth bug"
    run_detect "minimal"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^SCENARIO=hotfix$'
}

@test "default keyword: subject 'hotfix(scope): foo' → scenario=hotfix" {
    seed_head_commit "hotfix(auth): fix session expiry"
    run_detect "minimal"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^SCENARIO=hotfix$'
}

@test "default keyword: subject 'hotfixed: foo' → NO match (regression false positive)" {
    seed_head_commit "hotfixed: this is not a hotfix prefix"
    run_detect "minimal"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^SCENARIO=development_release$'
}

@test "default keyword: subject 'pre-hotfix: foo' → NO match (prefix not at start)" {
    seed_head_commit "pre-hotfix: preparation work"
    run_detect "minimal"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^SCENARIO=development_release$'
}

@test "default keyword: subject 'a hotfix: foo' → NO match (word not at start)" {
    seed_head_commit "a hotfix: is needed here"
    run_detect "minimal"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^SCENARIO=development_release$'
}

@test "default keyword: subject 'feat: foo' → scenario=development_release" {
    seed_head_commit "feat: add new feature"
    run_detect "minimal"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^SCENARIO=development_release$'
}

@test "default keyword: subject 'fix: foo' → scenario=development_release (fix is not hotfix)" {
    seed_head_commit "fix: resolve minor bug"
    run_detect "minimal"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^SCENARIO=development_release$'
}

# =============================================================================
# Bloque 2 — Custom keyword via fixture
# =============================================================================

@test "custom keyword 'urgent': subject 'urgent: foo' → scenario=hotfix" {
    # Write inline fixture with custom keyword
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
hotfix:
  keyword: "urgent"
EOF
    cd "${BATS_TEST_TMPDIR}/repo" || return 1
    echo "artifact" > artifact.txt
    git add -A >/dev/null
    git commit -q -m "urgent: fix critical payment bug"

    run flock "$LOCKFILE" sh -c "
        cd '${BATS_TEST_TMPDIR}/repo' && \
        sh '${PIPE_DIR}/detection/detect-scenario.sh' >/dev/null 2>&1 ; \
        cat /tmp/scenario.env 2>/dev/null
    "
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^SCENARIO=hotfix$'
}

@test "custom keyword 'urgent': subject 'urgent(prod): foo' → scenario=hotfix" {
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
hotfix:
  keyword: "urgent"
EOF
    cd "${BATS_TEST_TMPDIR}/repo" || return 1
    echo "artifact" > artifact.txt
    git add -A >/dev/null
    git commit -q -m "urgent(prod): rollback bad migration"

    run flock "$LOCKFILE" sh -c "
        cd '${BATS_TEST_TMPDIR}/repo' && \
        sh '${PIPE_DIR}/detection/detect-scenario.sh' >/dev/null 2>&1 ; \
        cat /tmp/scenario.env 2>/dev/null
    "
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^SCENARIO=hotfix$'
}

@test "custom keyword 'urgent': subject 'hotfix: foo' → NO match (keyword isolation)" {
    # When the consumer customizes the keyword, the default "hotfix" must NOT match.
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
hotfix:
  keyword: "urgent"
EOF
    cd "${BATS_TEST_TMPDIR}/repo" || return 1
    echo "artifact" > artifact.txt
    git add -A >/dev/null
    git commit -q -m "hotfix: this should NOT trigger the hotfix scenario"

    run flock "$LOCKFILE" sh -c "
        cd '${BATS_TEST_TMPDIR}/repo' && \
        sh '${PIPE_DIR}/detection/detect-scenario.sh' >/dev/null 2>&1 ; \
        cat /tmp/scenario.env 2>/dev/null
    "
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^SCENARIO=development_release$'
}

@test "custom keyword 'branch_hotfix': subject 'branch_hotfix: foo' → scenario=hotfix" {
    # Test user's explicit example: keyword with underscore
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
hotfix:
  keyword: "branch_hotfix"
EOF
    cd "${BATS_TEST_TMPDIR}/repo" || return 1
    echo "artifact" > artifact.txt
    git add -A >/dev/null
    git commit -q -m "branch_hotfix: custom keyword works"

    run flock "$LOCKFILE" sh -c "
        cd '${BATS_TEST_TMPDIR}/repo' && \
        sh '${PIPE_DIR}/detection/detect-scenario.sh' >/dev/null 2>&1 ; \
        cat /tmp/scenario.env 2>/dev/null
    "
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^SCENARIO=hotfix$'
}

@test "custom keyword 'branch_hotfix': subject 'branch_hotfixed: foo' → NO match" {
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
hotfix:
  keyword: "branch_hotfix"
EOF
    cd "${BATS_TEST_TMPDIR}/repo" || return 1
    echo "artifact" > artifact.txt
    git add -A >/dev/null
    git commit -q -m "branch_hotfixed: extended word should not match"

    run flock "$LOCKFILE" sh -c "
        cd '${BATS_TEST_TMPDIR}/repo' && \
        sh '${PIPE_DIR}/detection/detect-scenario.sh' >/dev/null 2>&1 ; \
        cat /tmp/scenario.env 2>/dev/null
    "
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^SCENARIO=development_release$'
}

# =============================================================================
# Bloque 3 — Merge commit parent-2 check (traditional 3-way merge)
# =============================================================================

@test "merge commit: HEAD='Merge pull request' + parent 2 'hotfix: foo' → scenario=hotfix" {
    seed_merge_commit_with_branch_tip "hotfix: critical auth fix"
    run_detect "minimal"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^SCENARIO=hotfix$'
}

@test "merge commit: HEAD='Merge pull request' + parent 2 'hotfix(scope): foo' → scenario=hotfix" {
    seed_merge_commit_with_branch_tip "hotfix(payment): retry on timeout"
    run_detect "minimal"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^SCENARIO=hotfix$'
}

@test "merge commit: HEAD='Merge pull request' + parent 2 'feat: foo' → scenario=development_release" {
    seed_merge_commit_with_branch_tip "feat: add analytics integration"
    run_detect "minimal"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^SCENARIO=development_release$'
}

@test "single-parent commit with regular subject: no parent-2 check" {
    # Confirm the parent-2 path only fires when HEAD is actually a merge commit
    seed_head_commit "chore: routine maintenance"
    run_detect "minimal"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^SCENARIO=development_release$'
}

# =============================================================================
# Bloque 4 — Multi-keyword detection (glob pattern list from config)
# =============================================================================

@test "multi-keyword: subject 'hotfix: foo' → scenario=hotfix (pattern hotfix:*)" {
    seed_head_commit "hotfix: fix auth bug"
    run_detect "multi-keyword"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^SCENARIO=hotfix$'
}

@test "multi-keyword: subject 'hotfix(scope): foo' → scenario=hotfix (pattern hotfix(*)" {
    seed_head_commit "hotfix(auth): fix session expiry"
    run_detect "multi-keyword"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^SCENARIO=hotfix$'
}

@test "multi-keyword: subject 'Hotfix/test patch' → scenario=hotfix (pattern [Hh]otfix/*)" {
    seed_head_commit "Hotfix/test patch"
    run_detect "multi-keyword"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^SCENARIO=hotfix$'
}

@test "multi-keyword: subject 'hotfix/fix-auth-bypass' → scenario=hotfix (lowercase)" {
    seed_head_commit "hotfix/fix-auth-bypass"
    run_detect "multi-keyword"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^SCENARIO=hotfix$'
}

@test "multi-keyword: subject 'feat: add feature' → scenario=development_release" {
    seed_head_commit "feat: add new feature"
    run_detect "multi-keyword"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^SCENARIO=development_release$'
}

@test "multi-keyword: subject 'Hotfixed/something' → NO match (false positive guard)" {
    seed_head_commit "Hotfixed/something unexpected"
    run_detect "multi-keyword"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^SCENARIO=development_release$'
}

# =============================================================================
# Bloque 5 — Custom multi-keyword list (isolation test)
# =============================================================================

@test "custom multi-keyword: 'urgent: foo' → scenario=hotfix" {
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
hotfix:
  keyword:
    - "urgent:*"
    - "critical(*"
EOF
    cd "${BATS_TEST_TMPDIR}/repo" || return 1
    echo "artifact" > artifact.txt
    git add -A >/dev/null
    git commit -q -m "urgent: fix payment gateway"

    run flock "$LOCKFILE" sh -c "
        cd '${BATS_TEST_TMPDIR}/repo' && \
        sh '${PIPE_DIR}/detection/detect-scenario.sh' >/dev/null 2>&1 ; \
        cat /tmp/scenario.env 2>/dev/null
    "
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^SCENARIO=hotfix$'
}

@test "custom multi-keyword: 'critical(prod): foo' → scenario=hotfix" {
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
hotfix:
  keyword:
    - "urgent:*"
    - "critical(*"
EOF
    cd "${BATS_TEST_TMPDIR}/repo" || return 1
    echo "artifact" > artifact.txt
    git add -A >/dev/null
    git commit -q -m "critical(prod): rollback bad migration"

    run flock "$LOCKFILE" sh -c "
        cd '${BATS_TEST_TMPDIR}/repo' && \
        sh '${PIPE_DIR}/detection/detect-scenario.sh' >/dev/null 2>&1 ; \
        cat /tmp/scenario.env 2>/dev/null
    "
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^SCENARIO=hotfix$'
}

@test "custom multi-keyword: 'hotfix: foo' → NO match (keyword isolation)" {
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
hotfix:
  keyword:
    - "urgent:*"
    - "critical(*"
EOF
    cd "${BATS_TEST_TMPDIR}/repo" || return 1
    echo "artifact" > artifact.txt
    git add -A >/dev/null
    git commit -q -m "hotfix: this should NOT trigger"

    run flock "$LOCKFILE" sh -c "
        cd '${BATS_TEST_TMPDIR}/repo' && \
        sh '${PIPE_DIR}/detection/detect-scenario.sh' >/dev/null 2>&1 ; \
        cat /tmp/scenario.env 2>/dev/null
    "
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^SCENARIO=development_release$'
}

# =============================================================================
# Bloque 6 — Merge commit parent-2 with multi-keyword patterns
# =============================================================================

@test "multi-keyword merge commit: parent 2 'Hotfix/branch-name' → scenario=hotfix" {
    seed_merge_commit_with_branch_tip "Hotfix/fix-critical-auth"
    run_detect "multi-keyword"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '^SCENARIO=hotfix$'
}
