#!/usr/bin/env bash
# ============================================================================
# Script: check-commit-hygiene.sh
# Description: Lints commit messages for GitHub Actions workflow-skip
#              substrings that silently skip all workflows for a push.
#
# GitHub Actions substring-matches the following anywhere in a commit
# message (subject or body) and skips every workflow for that push:
#
#   [skip ci]   [ci skip]   [no ci]   [skip actions]   [actions skip]
#   skip-checks: true   (as a commit trailer)
#
# The match is case-insensitive, so `[Skip CI]` and `[SKIP CI]` skip too.
#
# Two contexts that MUST keep working:
#   1. The pipe's own atomic-push commits from scripts/changelog/update-changelog.sh
#      legitimately carry `[skip ci]` to break the tag-on-merge infinite loop.
#      Detected here via subject prefix `chore(release):` or `chore(hotfix):`.
#   2. Rare human-initiated skip PRs (e.g. pure docs) can opt in explicitly
#      with the commit trailer `X-Intentional-Skip-CI: true`.
#
# Modes:
#   -m "msg"   inline commit message
#   -f path    commit message file (e.g. .git/COMMIT_EDITMSG)
#   -p N       PR number — fetches title, body, and per-commit messages via gh
# ============================================================================

set -euo pipefail

FORBIDDEN_PATTERNS=(
    '[skip ci]'
    '[ci skip]'
    '[no ci]'
    '[skip actions]'
    '[actions skip]'
    'skip-checks: true'
)

EXEMPT_TRAILER='X-Intentional-Skip-CI: true'
PIPE_AUTHOR_SUBJECT_RE='^chore\((release|hotfix)\):'

usage() {
    cat <<'EOF'
Usage:
  check-commit-hygiene.sh -m "commit message"
  check-commit-hygiene.sh -f path/to/commit-message-file
  check-commit-hygiene.sh -p PR_NUMBER

Lints a commit message (or all commits and the squash-merge body of a
PR) for GitHub Actions workflow-skip substrings. Exits 0 when clean,
1 when a forbidden substring is found, 2 on usage or argument errors.

Exemption: include the trailer `X-Intentional-Skip-CI: true` on its
own line in the commit body to bypass the lint for that specific
message. Use sparingly — the trailer documents the intent.

Pipe-authored commits whose subject starts with `chore(release):` or
`chore(hotfix):` are allowed to contain the skip markers. These are
the atomic-push circuit breakers that MUST keep working.
EOF
}

# Check one logical message (subject + body). Prints error lines on stderr
# for every forbidden substring found. Returns 0 when clean, 1 when dirty.
check_message() {
    local msg="$1"
    local label="${2:-commit message}"

    local subject
    subject=$(printf '%s' "$msg" | head -n1)

    if printf '%s' "$subject" | grep -Eq "$PIPE_AUTHOR_SUBJECT_RE"; then
        return 0
    fi

    if printf '%s\n' "$msg" | grep -Fxq "$EXEMPT_TRAILER"; then
        return 0
    fi

    local dirty=0
    local pattern
    for pattern in "${FORBIDDEN_PATTERNS[@]}"; do
        if printf '%s' "$msg" | grep -iFq -- "$pattern"; then
            printf 'ERROR: %s contains forbidden substring: %s\n' "$label" "$pattern" >&2
            dirty=1
        fi
    done

    return "$dirty"
}

print_remediation() {
    cat >&2 <<'EOF'

This commit or PR contains one or more GitHub Actions workflow-skip
substrings. GitHub Actions substring-matches these anywhere in the
message (case-insensitive) and will silently skip every workflow on
the resulting push. That is exactly how PR #34 landed on main without
a tag, a CHANGELOG, or a release image (see Finding #16).

See: CONTRIBUTING.md — "Commit Message Hygiene" section.

Safe alternatives when documenting the behavior:
  - skip-ci              (with a dash)
  - "skip ci"            (in quotes, without brackets)
  - the CI skip directive
  - the atomic push marker
  - the workflow-skip pragma

Intentional exemption: add the trailer
  X-Intentional-Skip-CI: true
on its own line in the commit body (or PR body). The exemption is
logged and reviewed — use it only when a skip is genuinely desired.
EOF
}

main() {
    local mode="" arg=""

    if [[ $# -eq 0 ]]; then
        usage >&2
        exit 2
    fi

    while getopts ":m:f:p:h" opt; do
        case "$opt" in
            m) mode="message"; arg="$OPTARG" ;;
            f) mode="file";    arg="$OPTARG" ;;
            p) mode="pr";      arg="$OPTARG" ;;
            h) usage; exit 0 ;;
            \?) printf 'ERROR: unknown flag: -%s\n' "$OPTARG" >&2; usage >&2; exit 2 ;;
            :)  printf 'ERROR: -%s requires an argument\n' "$OPTARG" >&2; exit 2 ;;
        esac
    done

    if [[ -z "$mode" ]]; then
        usage >&2
        exit 2
    fi

    local status=0

    case "$mode" in
        message)
            check_message "$arg" "commit message" || status=1
            ;;
        file)
            if [[ ! -r "$arg" ]]; then
                printf 'ERROR: cannot read file: %s\n' "$arg" >&2
                exit 2
            fi
            local content
            content=$(< "$arg")
            check_message "$content" "commit message file ($arg)" || status=1
            ;;
        pr)
            command -v gh >/dev/null 2>&1 || {
                printf 'ERROR: gh CLI is required for -p mode\n' >&2
                exit 2
            }
            command -v jq >/dev/null 2>&1 || {
                printf 'ERROR: jq is required for -p mode\n' >&2
                exit 2
            }

            local pr_json
            pr_json=$(gh pr view "$arg" --json title,body,commits,author)

            local pr_author
            pr_author=$(printf '%s' "$pr_json" | jq -r '.author.login // ""')
            if [[ "$pr_author" == "dependabot[bot]" || "$pr_author" == "renovate[bot]" ]]; then
                printf 'INFO: PR #%s authored by %s — skipping commit hygiene lint (bot-generated body may contain upstream skip markers)\n' "$arg" "$pr_author"
                exit 0
            fi

            local title body
            title=$(printf '%s' "$pr_json" | jq -r '.title // ""')
            body=$(printf '%s' "$pr_json" | jq -r '.body // ""')

            # GitHub's squash-merge message is PR title + PR body combined,
            # so that is what substring-matching will actually see on main.
            local squash_msg
            squash_msg=$(printf '%s\n\n%s' "$title" "$body")
            check_message "$squash_msg" "PR #$arg (squash-merge message)" || status=1

            local commit_count
            commit_count=$(printf '%s' "$pr_json" | jq '.commits | length')

            local i=0
            while [[ $i -lt $commit_count ]]; do
                local headline body_part full
                headline=$(printf '%s' "$pr_json" | jq -r ".commits[$i].messageHeadline // \"\"")
                body_part=$(printf '%s' "$pr_json" | jq -r ".commits[$i].messageBody // \"\"")
                if [[ -n "$body_part" ]]; then
                    full=$(printf '%s\n\n%s' "$headline" "$body_part")
                else
                    full="$headline"
                fi
                check_message "$full" "PR #$arg commit $((i + 1))/$commit_count" || status=1
                i=$((i + 1))
            done
            ;;
    esac

    if [[ "$status" -ne 0 ]]; then
        print_remediation
    fi

    exit "$status"
}

main "$@"
