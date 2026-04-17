#!/usr/bin/env bash
# sandbox-audit.sh — audit all 20 sandbox branches in the test repo
#
# Checks:
#   - Branch exists
#   - .versioning.yml is present and major.initial == N
#   - Special fixtures present (sandboxes 16-20)
#   - No orphan test/auto-* temp branches
#   - No leftover tags in the sandbox's namespace (vN.*)
#
# Usage:
#   ./sandbox-audit.sh             # audit all 20 sandboxes
#   ./sandbox-audit.sh 7           # audit only sandbox-07
#
# Not wired into CI — run manually for operational hygiene.
# Requirements: gh CLI authenticated, jq, base64, python3 (for base64 decode fallback)

set -euo pipefail

REPO="PanoraGrowth/panora-versioning-pipe-test"
SINGLE_SANDBOX=""
ERRORS=0
WARNINGS=0

for arg in "$@"; do
    case "$arg" in
        [0-9]|[0-9][0-9]) SINGLE_SANDBOX="$arg" ;;
        *) printf 'Unknown argument: %s\n' "$arg" >&2; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
OK()   { printf '  [OK]   %s\n' "$*"; }
FAIL() { printf '  [FAIL] %s\n' "$*"; ERRORS=$((ERRORS + 1)); }
WARN() { printf '  [WARN] %s\n' "$*"; WARNINGS=$((WARNINGS + 1)); }
INFO() { printf '  [INFO] %s\n' "$*"; }

b64dec() {
    # portable base64 decode (macOS uses base64 -D, Linux uses base64 -d)
    if base64 --version 2>&1 | grep -q GNU; then
        printf '%s' "$1" | base64 -d
    else
        printf '%s' "$1" | base64 -D
    fi
}

get_file_content_raw() {
    branch="$1"
    path="$2"
    gh api "repos/${REPO}/contents/${path}?ref=${branch}" --jq '.content' 2>/dev/null \
        | tr -d '\n' || echo ""
}

# ---------------------------------------------------------------------------
# Audit a single sandbox
# ---------------------------------------------------------------------------
audit_sandbox() {
    n="$1"  # 1..20 (numeric)
    branch="sandbox-$(printf '%02d' "$n")"
    printf '\n--- %s ---\n' "$branch"

    # 1. Branch exists?
    branch_sha=$(gh api "repos/${REPO}/git/ref/heads/${branch}" --jq '.object.sha' 2>/dev/null || echo "")
    if [ -z "$branch_sha" ]; then
        FAIL "Branch does not exist"
        return
    fi
    OK "Branch exists (SHA: ${branch_sha:0:8})"

    # 2. .versioning.yml present and major.initial == N?
    yml_raw=$(get_file_content_raw "$branch" ".versioning.yml")
    if [ -z "$yml_raw" ]; then
        FAIL ".versioning.yml not found"
    else
        yml_decoded=$(b64dec "$yml_raw")
        # Extract major.initial using grep (portable, no yq dependency)
        major_initial=$(printf '%s' "$yml_decoded" | grep -A2 'major:' | grep 'initial:' | head -1 | grep -oE '[0-9]+' || echo "")
        if [ "$major_initial" = "$n" ]; then
            OK ".versioning.yml present, major.initial=${major_initial}"
        elif [ -z "$major_initial" ]; then
            FAIL ".versioning.yml present but major.initial not found"
        else
            FAIL ".versioning.yml major.initial=${major_initial}, expected ${n}"
        fi

        # Check tag_on points to this sandbox
        tag_on=$(printf '%s' "$yml_decoded" | grep 'tag_on:' | head -1 | awk '{print $2}' || echo "")
        if [ "$tag_on" = "$branch" ]; then
            OK "tag_on: ${tag_on}"
        else
            FAIL "tag_on: '${tag_on}', expected '${branch}'"
        fi
    fi

    # 3. Special fixtures for sandboxes 16-20
    case "$n" in
        16) check_file_exists "$branch" "services/001-cluster-ecs/README.md" ;;
        17)
            check_file_exists "$branch" "backend/README.md"
            check_file_exists "$branch" "frontend/README.md"
            ;;
        18)
            check_file_exists "$branch" "backend/README.md"
            check_file_exists "$branch" "frontend/README.md"
            ;;
        19)
            check_file_exists "$branch" "services/version.yaml"
            check_file_exists "$branch" "services/README.md"
            ;;
        20)
            check_file_exists "$branch" "services/version.yaml"
            check_file_exists "$branch" "infrastructure/README.md"
            ;;
    esac

    # 4. Leftover tags in this sandbox's namespace (vN.*)
    tag_prefix="v${n}."
    leftover_tags=$(gh api "repos/${REPO}/git/refs/tags" \
        --jq "[.[] | select(.ref | startswith(\"refs/tags/${tag_prefix}\")) | .ref] | length" \
        2>/dev/null || echo "0")
    if [ "$leftover_tags" -eq 0 ]; then
        OK "No leftover tags in namespace ${tag_prefix}*"
    else
        WARN "${leftover_tags} leftover tag(s) in namespace ${tag_prefix}* — run cleanup if stale"
        # List them
        gh api "repos/${REPO}/git/refs/tags" \
            --jq ".[] | select(.ref | startswith(\"refs/tags/${tag_prefix}\")) | .ref" \
            2>/dev/null | while IFS= read -r t; do INFO "  leftover: ${t}"; done
    fi

    # 5. Orphan temp branches for this sandbox (test/auto-*-* older than 24h hint)
    orphan_count=$(gh api "repos/${REPO}/branches" \
        --jq "[.[] | select(.name | startswith(\"test/auto-\")) | .name] | length" \
        2>/dev/null || echo "0")
    if [ "$orphan_count" -gt 0 ]; then
        WARN "${orphan_count} total orphan test/auto-* branch(es) found in repo (not sandbox-specific)"
    fi
}

check_file_exists() {
    branch="$1"
    path="$2"
    result=$(gh api "repos/${REPO}/contents/${path}?ref=${branch}" --jq '.name' 2>/dev/null || echo "")
    if [ -n "$result" ]; then
        OK "Fixture present: ${path}"
    else
        FAIL "Fixture missing: ${path}"
    fi
}

# ---------------------------------------------------------------------------
# Summary of all orphan branches (repo-wide, once at the end)
# ---------------------------------------------------------------------------
audit_orphans() {
    printf '\n--- Orphan temp branches (repo-wide) ---\n'
    orphans=$(gh api "repos/${REPO}/branches" \
        --jq '[.[] | select(.name | startswith("test/auto-")) | .name] | .[]' \
        2>/dev/null || true)
    if [ -z "$orphans" ]; then
        OK "No orphan test/auto-* branches found"
    else
        while IFS= read -r b; do
            WARN "Orphan branch: ${b}"
        done <<EOF
$orphans
EOF
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    printf '=== sandbox-audit.sh — %s ===\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf 'Repo: %s\n' "$REPO"

    if [ -n "$SINGLE_SANDBOX" ]; then
        n=$((10#$SINGLE_SANDBOX))
        if [ "$n" -lt 1 ] || [ "$n" -gt 20 ]; then
            printf 'ERROR: sandbox number must be 1-20\n' >&2
            exit 1
        fi
        audit_sandbox "$n"
    else
        i=1
        while [ "$i" -le 20 ]; do
            audit_sandbox "$i"
            i=$((i + 1))
        done
        audit_orphans
    fi

    printf '\n=== Audit complete: %d error(s), %d warning(s) ===\n' "$ERRORS" "$WARNINGS"
    if [ "$ERRORS" -gt 0 ]; then
        exit 1
    fi
}

main
