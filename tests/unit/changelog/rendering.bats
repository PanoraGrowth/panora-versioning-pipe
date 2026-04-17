#!/usr/bin/env bats

# rendering.bats — tests for changelog output rendering
#
# Covers: changelog.use_emojis (true/false), changelog.commit_url link,
# tickets.url link in changelog output.

load '../../helpers/setup'
load '../../helpers/assertions'

LOCKFILE="/tmp/.versioning-merged.lock"

setup() { common_setup; }

teardown() {
    common_teardown
    rm -f /tmp/scenario.env /tmp/.versioning-merged.yml \
          /tmp/next_version.txt /tmp/routed_commits.txt
}

# Run generate-changelog-last-commit.sh and capture the generated CHANGELOG.md
run_changelog_generator() {
    local scenario="${1:-development_release}"

    cd "${BATS_TEST_TMPDIR}/repo" || return 1

    echo "artifact" > artifact.txt
    git add artifact.txt .versioning.yml >/dev/null
    git commit -q -m "${COMMIT_MSG:-feat: add new feature}"

    run flock "$LOCKFILE" sh -c "
        echo 'SCENARIO=${scenario}' > /tmp/scenario.env ; \
        echo '1.0.0' > /tmp/next_version.txt ; \
        cd '${BATS_TEST_TMPDIR}/repo' && \
        sh '${PIPE_DIR}/changelog/generate-changelog-last-commit.sh' >/dev/null 2>&1 ; \
        cat CHANGELOG.md 2>/dev/null || true
    "
}

# =============================================================================
# changelog.use_emojis
# =============================================================================

@test "use_emojis: false — output has no emoji prefix on commit line" {
    write_inline_fixture '
commits:
  format: "conventional"
version:
  tag_prefix_v: false
  components:
    major: { enabled: true, initial: 0 }
    patch: { enabled: true, initial: 0 }
changelog:
  use_emojis: false
  include_author: false
  include_commit_link: false
  include_ticket_link: false
'
    COMMIT_MSG="feat: add new feature" run_changelog_generator
    [ "$status" -eq 0 ]

    # The commit line should start with "- feat:" (no emoji)
    echo "$output" | grep -qE '^- feat: add new feature$'
}

@test "use_emojis: true — output includes emoji prefix for known type" {
    write_inline_fixture '
commits:
  format: "conventional"
version:
  tag_prefix_v: false
  components:
    major: { enabled: true, initial: 0 }
    patch: { enabled: true, initial: 0 }
changelog:
  use_emojis: true
  include_author: false
  include_commit_link: false
  include_ticket_link: false
'
    COMMIT_MSG="feat: add new feature" run_changelog_generator
    [ "$status" -eq 0 ]

    # The feat emoji is 🚀 — line should start with "- 🚀 feat:"
    echo "$output" | grep -qE '^- 🚀 feat: add new feature$'
}

@test "use_emojis: true with fix type — includes 🐛 emoji" {
    write_inline_fixture '
commits:
  format: "conventional"
version:
  tag_prefix_v: false
  components:
    major: { enabled: true, initial: 0 }
    patch: { enabled: true, initial: 0 }
changelog:
  use_emojis: true
  include_author: false
  include_commit_link: false
  include_ticket_link: false
'
    COMMIT_MSG="fix: resolve null pointer" run_changelog_generator
    [ "$status" -eq 0 ]

    echo "$output" | grep -qE '^- 🐛 fix: resolve null pointer$'
}

# =============================================================================
# changelog.commit_url
# =============================================================================

@test "commit_url: empty — no commit link in output" {
    write_inline_fixture '
commits:
  format: "conventional"
version:
  tag_prefix_v: false
  components:
    major: { enabled: true, initial: 0 }
    patch: { enabled: true, initial: 0 }
changelog:
  use_emojis: false
  include_author: false
  include_commit_link: true
  include_ticket_link: false
  commit_url: ""
'
    COMMIT_MSG="feat: empty commit url test" run_changelog_generator
    [ "$status" -eq 0 ]

    # No commit link line should appear
    ! echo "$output" | grep -q 'Commit:'
}

@test "commit_url: configured — commit link appears in output" {
    write_inline_fixture '
commits:
  format: "conventional"
version:
  tag_prefix_v: false
  components:
    major: { enabled: true, initial: 0 }
    patch: { enabled: true, initial: 0 }
changelog:
  use_emojis: false
  include_author: false
  include_commit_link: true
  include_ticket_link: false
  commit_url: "https://github.com/org/repo/commit"
'
    COMMIT_MSG="feat: commit url test" run_changelog_generator
    [ "$status" -eq 0 ]

    # Should contain a markdown link with "Commit:" label
    echo "$output" | grep -qE '\[Commit: [a-f0-9]+\]\(https://github\.com/org/repo/commit/'
}

# =============================================================================
# tickets.url — link in changelog output
# =============================================================================

@test "tickets.url: configured — ticket link appears in changelog with ticket as text" {
    write_inline_fixture '
commits:
  format: "ticket"
tickets:
  prefixes: ["PROJ"]
  required: false
  url: "https://myproject.atlassian.net/browse"
version:
  tag_prefix_v: false
  components:
    major: { enabled: true, initial: 0 }
    patch: { enabled: true, initial: 0 }
changelog:
  use_emojis: false
  include_author: false
  include_commit_link: false
  include_ticket_link: true
  ticket_link_label: "View ticket"
'
    cd "${BATS_TEST_TMPDIR}/repo" || return 1

    echo "artifact" > artifact.txt
    git add artifact.txt .versioning.yml >/dev/null
    git commit -q -m "PROJ-42 - feat: add feature with ticket"

    run flock "$LOCKFILE" sh -c "
        echo 'SCENARIO=development_release' > /tmp/scenario.env ; \
        echo '1.0.0' > /tmp/next_version.txt ; \
        cd '${BATS_TEST_TMPDIR}/repo' && \
        sh '${PIPE_DIR}/changelog/generate-changelog-last-commit.sh' >/dev/null 2>&1 ; \
        cat CHANGELOG.md 2>/dev/null || true
    "
    [ "$status" -eq 0 ]

    # Should contain a ticket link with PROJ-42 as text
    echo "$output" | grep -q 'PROJ-42'
    echo "$output" | grep -qE '\[View ticket\]\(https://myproject\.atlassian\.net/browse/PROJ-42\)'
}
