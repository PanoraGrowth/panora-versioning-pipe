#!/usr/bin/env bash
# =============================================================================
# check-release-readiness.sh — automated subset of the release readiness
# checklist (see temp/review/release-readiness-checklist.md).
#
# Runs a series of independent checks against the current working tree and
# the PR diff (relative to BASE_REF, default origin/main). Each check is a
# function returning 0 on PASS, 1 on FAIL, 2 on UNCLEAR (skipped because the
# signal is missing, not because anything is wrong).
#
# Exit code: 0 if zero FAILs, otherwise 1. UNCLEAR never fails the gate but
# is surfaced in the summary so a human can investigate.
#
# Dependencies: bash, git, rg (ripgrep), yq. jq and gh are not required.
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

BASE_REF="${BASE_REF:-origin/main}"
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

MAX_DOC_AGE_DAYS=14
MIN_UNIT_TEST_COUNT=207
CONSUMER_IMAGE="public.ecr.aws/k5n8p2t3/panora-versioning-pipe"

FORBIDDEN_COMMIT_MARKERS=(
    '[skip ci]'
    '[ci skip]'
    '[no ci]'
    '[skip actions]'
    '[actions skip]'
    '***NO_CI***'
)

# -----------------------------------------------------------------------------
# State
# -----------------------------------------------------------------------------

PASS_COUNT=0
FAIL_COUNT=0
UNCLEAR_COUNT=0
RESULTS=()

record() {
    local status="$1" name="$2" reason="${3:-}"
    case "$status" in
        PASS)    PASS_COUNT=$((PASS_COUNT+1));    RESULTS+=("[PASS] $name") ;;
        FAIL)    FAIL_COUNT=$((FAIL_COUNT+1));    RESULTS+=("[FAIL] $name: $reason") ;;
        UNCLEAR) UNCLEAR_COUNT=$((UNCLEAR_COUNT+1)); RESULTS+=("[UNCLEAR] $name: $reason") ;;
    esac
}

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

# Changed files in the PR (empty if BASE_REF is unreachable).
pr_changed_files() {
    local base
    if ! base=$(git merge-base "$BASE_REF" HEAD 2>/dev/null); then
        return 1
    fi
    git diff --name-only "$base" HEAD
}

# PR commits (empty if BASE_REF unreachable).
pr_commit_range() {
    local base
    if ! base=$(git merge-base "$BASE_REF" HEAD 2>/dev/null); then
        return 1
    fi
    echo "${base}..HEAD"
}

file_touched_in_pr() {
    local target="$1" changed
    if ! changed=$(pr_changed_files 2>/dev/null); then
        return 2
    fi
    printf '%s\n' "$changed" | grep -Fxq "$target"
}

# -----------------------------------------------------------------------------
# Checks
# -----------------------------------------------------------------------------

# a. CHANGELOG.md modified in this PR, OR PR is docs/meta-only.
check_changelog_has_entry() {
    local name="changelog_has_entry" changed
    if ! changed=$(pr_changed_files 2>/dev/null); then
        record UNCLEAR "$name" "cannot compute diff against $BASE_REF"
        return
    fi
    if [ -z "$changed" ]; then
        record PASS "$name"
        return
    fi
    if printf '%s\n' "$changed" | grep -Fxq "CHANGELOG.md"; then
        record PASS "$name"
        return
    fi
    # Docs-only PRs don't need a CHANGELOG bump.
    local code_changes
    code_changes=$(printf '%s\n' "$changed" | grep -E '^(scripts/|pipe\.sh$|Dockerfile$|Makefile$|tests/)' || true)
    if [ -z "$code_changes" ]; then
        record PASS "$name"
    else
        record FAIL "$name" "code files changed but CHANGELOG.md untouched"
    fi
}

# Shared timestamp check: verify `**Last updated:** YYYY-MM-DD` within window.
_check_doc_timestamp() {
    local name="$1" file="$2"
    if ! file_touched_in_pr "$file"; then
        local rc=$?
        if [ "$rc" = "2" ]; then
            record UNCLEAR "$name" "cannot compute diff against $BASE_REF"
            return
        fi
        record PASS "$name"
        return
    fi
    if [ ! -f "$file" ]; then
        record FAIL "$name" "$file modified in PR but missing from tree"
        return
    fi
    local stamp
    stamp=$(rg -oN -m 1 '\*\*Last updated:\*\*\s+(\d{4}-\d{2}-\d{2})' -r '$1' "$file" || true)
    if [ -z "$stamp" ]; then
        record FAIL "$name" "$file modified but no '**Last updated:** YYYY-MM-DD' line"
        return
    fi
    local now stamp_epoch now_epoch age_days
    now=$(date -u +%s)
    if ! stamp_epoch=$(date -j -f "%Y-%m-%d" "$stamp" "+%s" 2>/dev/null); then
        if ! stamp_epoch=$(date -d "$stamp" "+%s" 2>/dev/null); then
            record UNCLEAR "$name" "could not parse date '$stamp'"
            return
        fi
    fi
    now_epoch=$now
    age_days=$(( (now_epoch - stamp_epoch) / 86400 ))
    if [ "$age_days" -lt 0 ]; then
        record FAIL "$name" "$file timestamp $stamp is in the future"
    elif [ "$age_days" -gt "$MAX_DOC_AGE_DAYS" ]; then
        record FAIL "$name" "$file timestamp $stamp is $age_days days old (max $MAX_DOC_AGE_DAYS)"
    else
        record PASS "$name"
    fi
}

# b. README.md freshness (when touched).
check_readme_timestamp() {
    _check_doc_timestamp "readme_timestamp" "README.md"
}

# c. docs/architecture/README.md freshness (when touched).
check_architecture_timestamp() {
    _check_doc_timestamp "architecture_timestamp" "docs/architecture/README.md"
}

# d. No forbidden CI-skip substrings in PR commit messages.
check_commit_hygiene() {
    local name="commit_hygiene" range
    if ! range=$(pr_commit_range 2>/dev/null); then
        record UNCLEAR "$name" "cannot compute commit range against $BASE_REF"
        return
    fi
    local messages
    messages=$(git log --format='%B%x1e' "$range" 2>/dev/null || true)
    if [ -z "$messages" ]; then
        record PASS "$name"
        return
    fi
    local offenders=""
    for marker in "${FORBIDDEN_COMMIT_MARKERS[@]}"; do
        if printf '%s' "$messages" | grep -Fq -- "$marker"; then
            offenders+=" '$marker'"
        fi
    done
    if [ -n "$offenders" ]; then
        record FAIL "$name" "forbidden substrings found in PR commit messages:${offenders}"
    else
        record PASS "$name"
    fi
}

# e. Unit test count does not regress below the known floor.
check_unit_test_count() {
    local name="unit_test_count"
    if ! command -v rg >/dev/null 2>&1; then
        record UNCLEAR "$name" "rg not available"
        return
    fi
    local count
    count=$(rg --glob '*.bats' -c '^@test ' tests/ 2>/dev/null | awk -F: '{s+=$2} END {print s+0}' || true)
    if [ -z "$count" ] || [ "$count" = "0" ]; then
        record UNCLEAR "$name" "could not count @test definitions under tests/"
        return
    fi
    if [ "$count" -lt "$MIN_UNIT_TEST_COUNT" ]; then
        record FAIL "$name" "found $count @test definitions, expected >= $MIN_UNIT_TEST_COUNT"
    else
        record PASS "$name"
    fi
}

# f. Every top-level defaults.yml key is actually read by config-parser.sh.
check_defaults_keys_have_getters() {
    local name="defaults_keys_have_getters"
    local defaults_file="scripts/defaults.yml"
    local parser_file="scripts/lib/config-parser.sh"
    if [ ! -f "$defaults_file" ] || [ ! -f "$parser_file" ]; then
        record UNCLEAR "$name" "defaults.yml or config-parser.sh missing"
        return
    fi
    if ! command -v yq >/dev/null 2>&1; then
        record UNCLEAR "$name" "yq not available"
        return
    fi
    local keys missing=""
    keys=$(yq 'keys | .[]' "$defaults_file" 2>/dev/null || true)
    if [ -z "$keys" ]; then
        record UNCLEAR "$name" "yq returned no top-level keys"
        return
    fi
    # Keys consumed outside config-parser.sh (documented exceptions — see
    # scripts/reporting/notify-teams.sh for notifications.*).
    local exempt=" notifications commit_types "
    while IFS= read -r key; do
        [ -z "$key" ] && continue
        if [[ "$exempt" == *" $key "* ]]; then
            # Still require the key to be consumed somewhere in scripts/.
            if ! rg -q "\.${key}\." "$parser_file" scripts/ 2>/dev/null && \
               ! rg -q "${key}" "$parser_file" 2>/dev/null; then
                missing+=" $key"
            fi
            continue
        fi
        if ! rg -q "config_get(_array)?[[:space:]]+\"${key}\." "$parser_file"; then
            missing+=" $key"
        fi
    done <<< "$keys"
    if [ -n "$missing" ]; then
        record FAIL "$name" "defaults.yml keys without a getter in config-parser.sh:${missing}"
    else
        record PASS "$name"
    fi
}

# g. examples/github-actions/*.yml all reference the current consumer image.
check_example_image_urls() {
    local name="example_image_urls"
    local dir="examples/github-actions"
    if [ ! -d "$dir" ]; then
        record UNCLEAR "$name" "$dir missing"
        return
    fi
    local bad="" file
    for file in "$dir"/*.yml; do
        [ -f "$file" ] || continue
        # Only inspect lines that actually declare an image.
        local image_lines
        image_lines=$(rg -N '(docker://|image:\s*)[[:graph:]]+' "$file" || true)
        [ -z "$image_lines" ] && continue
        if ! printf '%s\n' "$image_lines" | grep -Fq "$CONSUMER_IMAGE"; then
            bad+=" $file"
            continue
        fi
        # Reject any image reference that ISN'T the expected consumer image.
        local other
        other=$(printf '%s\n' "$image_lines" | rg -v -F "$CONSUMER_IMAGE" | rg -N '(docker://|image:\s*)([[:graph:]]+/)+' || true)
        if [ -n "$other" ]; then
            bad+=" $file"
        fi
    done
    if [ -n "$bad" ]; then
        record FAIL "$name" "unexpected image reference in:${bad}"
    else
        record PASS "$name"
    fi
}

# h. Bitbucket example mirrors the same image.
check_bitbucket_example_image() {
    local name="bitbucket_example_image"
    local file="examples/bitbucket/bitbucket-pipelines.yml"
    if [ ! -f "$file" ]; then
        record UNCLEAR "$name" "$file missing"
        return
    fi
    if ! rg -Fq "$CONSUMER_IMAGE" "$file"; then
        record FAIL "$name" "$file does not reference $CONSUMER_IMAGE"
        return
    fi
    local other
    other=$(rg -N '^\s*image:\s*([[:graph:]]+)' -r '$1' "$file" | rg -v -F "$CONSUMER_IMAGE" || true)
    if [ -n "$other" ]; then
        record FAIL "$name" "$file has non-matching image references: $other"
    else
        record PASS "$name"
    fi
}

# -----------------------------------------------------------------------------
# Driver
# -----------------------------------------------------------------------------

main() {
    echo "=========================================="
    echo "  Release Readiness Gate"
    echo "=========================================="
    echo "  base_ref:  $BASE_REF"
    echo "  repo_root: $REPO_ROOT"
    echo

    check_changelog_has_entry
    check_readme_timestamp
    check_architecture_timestamp
    check_commit_hygiene
    check_unit_test_count
    check_defaults_keys_have_getters
    check_example_image_urls
    check_bitbucket_example_image

    local line
    for line in "${RESULTS[@]}"; do
        echo "$line"
    done

    echo
    echo "------------------------------------------"
    printf 'summary: %d pass, %d fail, %d unclear\n' \
        "$PASS_COUNT" "$FAIL_COUNT" "$UNCLEAR_COUNT"
    echo "------------------------------------------"

    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
        {
            echo "## Release Readiness Gate"
            echo
            echo "| status | check |"
            echo "| --- | --- |"
            for line in "${RESULTS[@]}"; do
                local status check
                status=$(printf '%s' "$line" | awk -F'] ' '{print $1"]"}')
                check=$(printf '%s' "$line" | awk -F'] ' '{print $2}')
                printf '| %s | %s |\n' "$status" "$check"
            done
            echo
            printf '**Summary:** %d pass · %d fail · %d unclear\n' \
                "$PASS_COUNT" "$FAIL_COUNT" "$UNCLEAR_COUNT"
        } >> "$GITHUB_STEP_SUMMARY"
    fi

    [ "$FAIL_COUNT" -eq 0 ]
}

main "$@"
