#!/usr/bin/env bats

# calculate-version-initial-respect.bats — ticket 055 end-to-end coverage
#
# Exercises the namespace filter introduced by build_initial_prefix_regex():
# `version.components.{epoch,major}.initial` is declarative authority — the
# next tag lives in the configured namespace regardless of existing tags.
# Progression components (patch, hotfix_counter) stay cold-start-only.
#
# Each @test seeds a temp git repo with fixture + N initial tags + a new
# commit, writes /tmp/scenario.env, runs calculate-version.sh under flock,
# and asserts NEXT_VERSION captured in the same locked shell.
#
# Fixture selection:
#   - semver (epoch=off, v-prefix=on, major+patch, hotfix_counter default=on):
#     Cases A, C, D, E, F, G
#   - with-hotfix-counter (epoch=on, v-prefix=on, all 4 components):
#     Case B, Case H
#   - inline custom fixtures for boundary tests

load '../../helpers/setup'
load '../../helpers/assertions'

LOCKFILE="/tmp/.versioning-merged.lock"

setup() { common_setup; }

teardown() {
    common_teardown
    rm -f /tmp/scenario.env /tmp/.versioning-merged.yml \
          /tmp/next_version.txt /tmp/bump_type.txt /tmp/latest_tag.txt
}

# Seed repo with fixture + list of initial tags + one new commit, then run
# calculate-version.sh under flock. Captures BUMP_TYPE + NEXT_VERSION from the
# state files inside the same locked shell so parallel tests cannot race.
#
# Usage: run_calculate_tags <fixture> <scenario> "<tag1 tag2 ...>" "<commit_msg>"
#   - pass "" for empty tag list (cold-start)
run_calculate_tags() {
    local fixture="$1"
    local scenario="$2"
    local tags="$3"
    local commit_msg="$4"

    cp "${PIPE_DIR}/tests/fixtures/${fixture}.yml" \
       "${BATS_TEST_TMPDIR}/repo/.versioning.yml"

    cd "${BATS_TEST_TMPDIR}/repo" || return 1

    # Tag the init commit with each seed tag. Git allows N tags on the same
    # commit; the filter logic cares about presence and sort order, not SHA.
    if [ -n "$tags" ]; then
        for t in $tags; do
            git tag "$t"
        done
    fi

    echo "artifact" > artifact.txt
    git add artifact.txt .versioning.yml >/dev/null
    git commit -q -m "$commit_msg"

    run flock "$LOCKFILE" sh -c "
        echo 'SCENARIO=${scenario}' > /tmp/scenario.env ; \
        cd '${BATS_TEST_TMPDIR}/repo' && \
        sh '${PIPE_DIR}/versioning/calculate-version.sh' >/tmp/calc.out 2>&1 ; \
        rc=\$? ; \
        echo BUMP_TYPE=\$(cat /tmp/bump_type.txt 2>/dev/null) ; \
        echo NEXT_VERSION=\$(cat /tmp/next_version.txt 2>/dev/null) ; \
        echo LATEST_TAG=\$(cat /tmp/latest_tag.txt 2>/dev/null) ; \
        cat /tmp/calc.out ; \
        exit \$rc
    "
}

# Inline variant for Case B (custom epoch config) — writes fixture from string.
run_calculate_inline() {
    local inline_yaml="$1"
    local scenario="$2"
    local tags="$3"
    local commit_msg="$4"

    printf '%s\n' "$inline_yaml" > "${BATS_TEST_TMPDIR}/repo/.versioning.yml"

    cd "${BATS_TEST_TMPDIR}/repo" || return 1

    if [ -n "$tags" ]; then
        for t in $tags; do
            git tag "$t"
        done
    fi

    echo "artifact" > artifact.txt
    git add artifact.txt .versioning.yml >/dev/null
    git commit -q -m "$commit_msg"

    run flock "$LOCKFILE" sh -c "
        echo 'SCENARIO=${scenario}' > /tmp/scenario.env ; \
        cd '${BATS_TEST_TMPDIR}/repo' && \
        sh '${PIPE_DIR}/versioning/calculate-version.sh' >/tmp/calc.out 2>&1 ; \
        rc=\$? ; \
        echo BUMP_TYPE=\$(cat /tmp/bump_type.txt 2>/dev/null) ; \
        echo NEXT_VERSION=\$(cat /tmp/next_version.txt 2>/dev/null) ; \
        echo LATEST_TAG=\$(cat /tmp/latest_tag.txt 2>/dev/null) ; \
        cat /tmp/calc.out ; \
        exit \$rc
    "
}

# =============================================================================
# Case A — Migration from another tool (semver fixture, epoch off, v-prefix on)
# =============================================================================
# Tags v1.* exist, major.initial: 2 → namespace ^v2\. is empty → cold start
# from MAJOR=2, PATCH=0. feat bumps PATCH → 1 → render v2.1 (hotfix_counter=0 omitted).

@test "Case A: tags v1.* + major.initial=2 + feat → v2.1 (new namespace cold start)" {
    local inline="commits:
  format: conventional
version:
  tag_prefix_v: true
  components:
    epoch:
      enabled: false
    major:
      enabled: true
      initial: 2
    patch:
      enabled: true
      initial: 0
    hotfix_counter:
      enabled: false
    timestamp:
      enabled: false"

    run_calculate_inline "$inline" "development_release" "v1.0.0 v1.5.2 v1.8.0" "feat: new login system"
    [ "$status" -eq 0 ]
    # Namespace filter must exclude all v1.* tags → LATEST_TAG line is empty
    echo "$output" | grep -qE '^LATEST_TAG=$'
    echo "$output" | grep -qE '^BUMP_TYPE=minor$'
    echo "$output" | grep -qE '^NEXT_VERSION=v2\.1$'
}

# =============================================================================
# Case B — Epoch rotation (epoch on, v-prefix on)
# =============================================================================
# Tags v0.5.2 v0.5.3 exist, epoch.initial: 1, major.initial: 0 → namespace
# ^v1\.0\. is empty → cold start: EPOCH=1, MAJOR=0, PATCH=0, HOTFIX=0.
# breaking bumps MAJOR 0→1, resets PATCH+HOTFIX → v1.1.0

@test "Case B: tags v0.5.* + epoch.initial=1, major.initial=0 + breaking → enters v1.* namespace" {
    local inline="commits:
  format: conventional
version:
  tag_prefix_v: true
  components:
    epoch:
      enabled: true
      initial: 1
    major:
      enabled: true
      initial: 0
    patch:
      enabled: true
      initial: 0
    hotfix_counter:
      enabled: false
    timestamp:
      enabled: false"

    run_calculate_inline "$inline" "development_release" "v0.5.2 v0.5.3" "breaking: redesign API"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qE '^LATEST_TAG=$'
    echo "$output" | grep -qE '^BUMP_TYPE=major$'
    # EPOCH=1, MAJOR=0→1 (breaking), PATCH=0 reset → v1.1.0
    echo "$output" | grep -qE '^NEXT_VERSION=v1\.1\.0$'
}

# =============================================================================
# Case C — Sandbox isolation (semver fixture)
# =============================================================================
# 3 tags in v0.* (simulating main's ~214 tags), major.initial: 7 → namespace
# ^v7\. is empty → cold start with MAJOR=7, PATCH=0. feat bumps PATCH → 1 → v7.1

@test "Case C: tags v0.* + major.initial=7 + feat → v7.1 (sandbox isolation)" {
    local inline="commits:
  format: conventional
version:
  tag_prefix_v: true
  components:
    epoch:
      enabled: false
    major:
      enabled: true
      initial: 7
    patch:
      enabled: true
      initial: 0
    hotfix_counter:
      enabled: false
    timestamp:
      enabled: false"

    run_calculate_inline "$inline" "development_release" "v0.214.0 v0.214.1 v0.214.2" "feat(auth): sandbox scenario"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qE '^LATEST_TAG=$'
    echo "$output" | grep -qE '^BUMP_TYPE=minor$'
    echo "$output" | grep -qE '^NEXT_VERSION=v7\.1$'
}

# =============================================================================
# Case D — Back-compat (unchanged behavior)
# =============================================================================
# Tags v2.1 v2.1.1 exist (hotfix counter off, so v2.1.1 is impossible under
# normal rendering). Use v2.0 v2.1 instead: namespace ^v2\. matches both → pick
# latest (v2.1) → fix bumps PATCH 1→2 → v2.2.

@test "Case D: tags v2.* + major.initial=2 + fix → v2.2 (back-compat)" {
    local inline="commits:
  format: conventional
version:
  tag_prefix_v: true
  components:
    epoch:
      enabled: false
    major:
      enabled: true
      initial: 2
    patch:
      enabled: true
      initial: 0
    hotfix_counter:
      enabled: false
    timestamp:
      enabled: false"

    run_calculate_inline "$inline" "development_release" "v2.0 v2.1" "fix: bug patch"
    [ "$status" -eq 0 ]
    # Namespace filter matches; latest tag v2.1 used as baseline
    echo "$output" | grep -qE '^LATEST_TAG=v2\.1$'
    echo "$output" | grep -qE '^BUMP_TYPE=patch$'
    echo "$output" | grep -qE '^NEXT_VERSION=v2\.2$'
}

# =============================================================================
# Case E — Intentional downgrade
# =============================================================================
# Tag v3.0 exists, major.initial: 2 → namespace ^v2\. is empty → cold start
# from MAJOR=2, PATCH=0. feat bumps PATCH → 1 → v2.1 (the downgrade lands
# cleanly; consumer declared they want to re-enter the v2.* namespace).

@test "Case E: tag v3.0 + major.initial=2 + feat → v2.1 (intentional downgrade)" {
    local inline="commits:
  format: conventional
version:
  tag_prefix_v: true
  components:
    epoch:
      enabled: false
    major:
      enabled: true
      initial: 2
    patch:
      enabled: true
      initial: 0
    hotfix_counter:
      enabled: false
    timestamp:
      enabled: false"

    run_calculate_inline "$inline" "development_release" "v3.0" "feat: something"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qE '^LATEST_TAG=$'
    echo "$output" | grep -qE '^BUMP_TYPE=minor$'
    echo "$output" | grep -qE '^NEXT_VERSION=v2\.1$'
}

# =============================================================================
# Case F — Collision with existing tag in target namespace
# =============================================================================
# Tag v5.0 exists (within target namespace), major.initial: 5 → namespace
# ^v5\. matches v5.0 → picks it as LATEST_TAG → feat bumps PATCH 0→1 → v5.1.

@test "Case F: tag v5.0 + major.initial=5 + feat → v5.1 (namespace collision resolves via bump)" {
    local inline="commits:
  format: conventional
version:
  tag_prefix_v: true
  components:
    epoch:
      enabled: false
    major:
      enabled: true
      initial: 5
    patch:
      enabled: true
      initial: 0
    hotfix_counter:
      enabled: false
    timestamp:
      enabled: false"

    run_calculate_inline "$inline" "development_release" "v5.0" "feat: something"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qE '^LATEST_TAG=v5\.0$'
    echo "$output" | grep -qE '^BUMP_TYPE=minor$'
    echo "$output" | grep -qE '^NEXT_VERSION=v5\.1$'
}

# =============================================================================
# Case G — patch.initial does NOT filter existing tags (progression)
# =============================================================================
# Tag v2.8 exists in target namespace (major.initial=2), patch.initial=5 is
# set but MUST NOT be applied — progression continues from latest tag. feat
# bumps PATCH 8→9 → v2.9. And the pipe emits the diagnostic log note.

@test "Case G: tags in namespace + patch.initial=5 + feat → progression from latest, not cold-start" {
    local inline="commits:
  format: conventional
version:
  tag_prefix_v: true
  components:
    epoch:
      enabled: false
    major:
      enabled: true
      initial: 2
    patch:
      enabled: true
      initial: 5
    hotfix_counter:
      enabled: false
    timestamp:
      enabled: false"

    run_calculate_inline "$inline" "development_release" "v2.8" "feat: something"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qE '^LATEST_TAG=v2\.8$'
    echo "$output" | grep -qE '^BUMP_TYPE=minor$'
    # Progression: patch 8 → 9; patch.initial=5 is NOT applied.
    echo "$output" | grep -qE '^NEXT_VERSION=v2\.9$'
    # Diagnostic log must fire
    echo "$output" | grep -q 'version.components.patch.initial=5 is ignored'
}

# =============================================================================
# Case H — hotfix_counter.initial does NOT filter existing tags (progression)
# =============================================================================
# with-hotfix-counter fixture: epoch+major+patch+hotfix_counter (v-prefix on).
# Tag v0.2.5.3 exists in namespace (epoch.initial=0, major.initial=2 by override),
# hotfix_counter.initial=7 set but MUST NOT be applied — progression continues
# from latest tag. hotfix bumps HOTFIX_COUNTER 3→4 → v0.2.5.4.

@test "Case H: tags in namespace + hotfix_counter.initial=7 + hotfix → progression from latest, not cold-start" {
    local inline="commits:
  format: conventional
version:
  tag_prefix_v: true
  components:
    epoch:
      enabled: true
      initial: 0
    major:
      enabled: true
      initial: 2
    patch:
      enabled: true
      initial: 0
    hotfix_counter:
      enabled: true
      initial: 7
    timestamp:
      enabled: false"

    run_calculate_inline "$inline" "hotfix" "v0.2.5 v0.2.5.3" "hotfix: urgent fix"
    [ "$status" -eq 0 ]
    # Latest tag in namespace ^v0\.2\. is v0.2.5.3
    echo "$output" | grep -qE '^LATEST_TAG=v0\.2\.5\.3$'
    echo "$output" | grep -qE '^BUMP_TYPE=patch$'
    # Progression: hotfix_counter 3 → 4; hotfix_counter.initial=7 is NOT applied.
    echo "$output" | grep -qE '^NEXT_VERSION=v0\.2\.5\.4$'
    # Diagnostic log must fire
    echo "$output" | grep -q 'version.components.hotfix_counter.initial=7 is ignored'
}

# =============================================================================
# Boundary test — v1 vs v10 vs v100 (regex anchoring)
# =============================================================================
# Repo has tags v1.0, v10.0, v100.0. With major.initial=1, the namespace filter
# ^v1\. MUST match ONLY v1.0, not v10.0 or v100.0. feat bumps PATCH 0→1 → v1.1.

@test "Boundary: v1 vs v10 vs v100 — major.initial=1 picks ONLY v1.*" {
    local inline="commits:
  format: conventional
version:
  tag_prefix_v: true
  components:
    epoch:
      enabled: false
    major:
      enabled: true
      initial: 1
    patch:
      enabled: true
      initial: 0
    hotfix_counter:
      enabled: false
    timestamp:
      enabled: false"

    run_calculate_inline "$inline" "development_release" "v1.0 v10.0 v100.0" "feat: boundary check"
    [ "$status" -eq 0 ]
    # If the \. boundary is dropped, this would pick v100.0 (sorted highest) and bump it.
    echo "$output" | grep -qE '^LATEST_TAG=v1\.0$'
    echo "$output" | grep -qE '^BUMP_TYPE=minor$'
    echo "$output" | grep -qE '^NEXT_VERSION=v1\.1$'
}

# =============================================================================
# Negative control — diagnostic log does NOT fire on default progression values
# =============================================================================

@test "No noise: patch.initial=0 (default) + tags in namespace → NO diagnostic log" {
    local inline="commits:
  format: conventional
version:
  tag_prefix_v: true
  components:
    epoch:
      enabled: false
    major:
      enabled: true
      initial: 2
    patch:
      enabled: true
      initial: 0
    hotfix_counter:
      enabled: false
    timestamp:
      enabled: false"

    run_calculate_inline "$inline" "development_release" "v2.3" "feat: something"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qE '^NEXT_VERSION=v2\.4$'
    ! echo "$output" | grep -q 'version.components.patch.initial='
    ! echo "$output" | grep -q 'version.components.hotfix_counter.initial='
}

# =============================================================================
# Cold start path still behaves correctly (no tags → initial values applied)
# =============================================================================

@test "Cold start: no tags in repo + major.initial=3 + feat → v3.1" {
    local inline="commits:
  format: conventional
version:
  tag_prefix_v: true
  components:
    epoch:
      enabled: false
    major:
      enabled: true
      initial: 3
    patch:
      enabled: true
      initial: 0
    hotfix_counter:
      enabled: false
    timestamp:
      enabled: false"

    run_calculate_inline "$inline" "development_release" "" "feat: bootstrap"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qE '^LATEST_TAG=$'
    echo "$output" | grep -qE '^BUMP_TYPE=minor$'
    echo "$output" | grep -qE '^NEXT_VERSION=v3\.1$'
}
