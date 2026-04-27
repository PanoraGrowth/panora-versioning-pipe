#!/usr/bin/env bash
# seed-sandboxes.sh — idempotent creation/update of sandbox-01..sandbox-34 branches
#                     in PanoraGrowth/panora-versioning-pipe-test
#
# Usage:
#   ./seed-sandboxes.sh              # create/update all sandboxes
#   ./seed-sandboxes.sh 3            # create/update only sandbox-03
#   ./seed-sandboxes.sh --dry-run    # print what would be done, no API calls
#
# Requirements: gh CLI authenticated, jq, base64
# POSIX-ish, shellcheck-clean

set -euo pipefail

REPO="PanoraGrowth/panora-versioning-pipe-test"
DRY_RUN=0
SINGLE_SANDBOX=""

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        [0-9]|[0-9][0-9]) SINGLE_SANDBOX="$arg" ;;
        *) echo "Unknown argument: $arg" >&2; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() { printf '[seed-sandboxes] %s\n' "$*"; }
die() { printf '[seed-sandboxes] ERROR: %s\n' "$*" >&2; exit 1; }

b64enc() {
    # portable base64 encode (macOS + Linux)
    printf '%s' "$1" | base64
}

gh_api() {
    if [ "$DRY_RUN" -eq 1 ]; then
        log "DRY-RUN: gh api $*"
        return 0
    fi
    gh api "$@"
}

# Get SHA of main branch HEAD
get_main_sha() {
    gh api "repos/${REPO}/git/ref/heads/main" --jq '.object.sha'
}

# Check if branch exists; return 0 if yes, 1 if no
branch_exists() {
    branch="$1"
    gh api "repos/${REPO}/git/ref/heads/${branch}" --silent 2>/dev/null && return 0
    return 1
}

# Create branch from SHA
create_branch() {
    branch="$1"
    sha="$2"
    gh_api "repos/${REPO}/git/refs" \
        --method POST \
        --field "ref=refs/heads/${branch}" \
        --field "sha=${sha}" \
        --silent
}

# Get file SHA on a branch (needed for updates); returns "" if file does not exist
get_file_sha() {
    branch="$1"
    path="$2"
    # gh api exits 1 on 404 and writes error JSON to stdout; capture+discard on failure
    if sha=$(gh api "repos/${REPO}/contents/${path}?ref=${branch}" --jq '.sha' 2>/dev/null); then
        printf '%s' "$sha"
    fi
    # returns "" implicitly when gh api exits non-zero
}

# Commit a single file on a branch
commit_file() {
    branch="$1"
    path="$2"
    content="$3"   # raw content (not yet encoded)
    message="$4"
    existing_sha="$5"  # pass "" if creating new file

    encoded=$(b64enc "$content")

    if [ -n "$existing_sha" ]; then
        gh_api "repos/${REPO}/contents/${path}" \
            --method PUT \
            --field "message=${message}" \
            --field "content=${encoded}" \
            --field "sha=${existing_sha}" \
            --field "branch=${branch}" \
            --silent
    else
        gh_api "repos/${REPO}/contents/${path}" \
            --method PUT \
            --field "message=${message}" \
            --field "content=${encoded}" \
            --field "branch=${branch}" \
            --silent
    fi
}

# ---------------------------------------------------------------------------
# Build .versioning.yml content for a sandbox
# This is the base config from the test repo with only major.initial and tag_on overridden.
# hotfix sandboxes (09-13) also get hotfix-compatible branches config.
# ---------------------------------------------------------------------------
build_versioning_yml() {
    sandbox_num="$1"  # 1..34 (no leading zero)
    n="$sandbox_num"

    cat <<YAML
commits:
  format: conventional
version:
  tag_prefix_v: true
  components:
    epoch:
      enabled: false
      initial: 0
    major:
      enabled: true
      initial: ${n}
    patch:
      enabled: true
      initial: 0
    hotfix_counter:
      enabled: true
      initial: 0
branches:
  development: sandbox-$(printf '%02d' "$n")
  production: sandbox-$(printf '%02d' "$n")
  tag_on: sandbox-$(printf '%02d' "$n")
  hotfix_targets:
  - sandbox-$(printf '%02d' "$n")
hotfix:
  keyword:
  - '^hotfix(\(|:)'
  - '^[Hh]otfix/'
  - 'URGENT-PATCH'
changelog:
  mode: full
  commit_url: https://github.com/PanoraGrowth/panora-versioning-pipe-test/commit
  include_author: true
  include_commit_link: true
  include_ticket_link: false
  per_folder:
    enabled: true
    folders:
    - backend
    - frontend
    scope_matching: exact
    fallback: file_path
YAML
}

# Build .versioning.yml for sandboxes 16-20 which need custom per_folder/version_file config
build_versioning_yml_16() {
    cat <<YAML
commits:
  format: conventional
version:
  tag_prefix_v: true
  components:
    epoch:
      enabled: false
      initial: 0
    major:
      enabled: true
      initial: 16
    patch:
      enabled: true
      initial: 0
    hotfix_counter:
      enabled: true
      initial: 0
branches:
  development: sandbox-16
  production: sandbox-16
  tag_on: sandbox-16
  hotfix_targets:
  - sandbox-16
hotfix:
  keyword:
  - "^hotfix(\\(|:)"
  - "^[Hh]otfix/"
  - "URGENT-PATCH"
changelog:
  mode: full
  commit_url: https://github.com/PanoraGrowth/panora-versioning-pipe-test/commit
  include_author: true
  include_commit_link: true
  include_ticket_link: false
  per_folder:
    enabled: true
    folders:
    - services
    scope_matching: suffix
    fallback: root
YAML
}

build_versioning_yml_17() {
    cat <<YAML
commits:
  format: conventional
version:
  tag_prefix_v: true
  components:
    epoch:
      enabled: false
      initial: 0
    major:
      enabled: true
      initial: 17
    patch:
      enabled: true
      initial: 0
    hotfix_counter:
      enabled: true
      initial: 0
branches:
  development: sandbox-17
  production: sandbox-17
  tag_on: sandbox-17
  hotfix_targets:
  - sandbox-17
hotfix:
  keyword:
  - '^hotfix(\(|:)'
  - '^[Hh]otfix/'
  - 'URGENT-PATCH'
changelog:
  mode: full
  commit_url: https://github.com/PanoraGrowth/panora-versioning-pipe-test/commit
  include_author: true
  include_commit_link: true
  include_ticket_link: false
  per_folder:
    enabled: true
    folders:
    - backend
    - frontend
    scope_matching: exact
    fallback: file_path
YAML
}

build_versioning_yml_18() {
    cat <<YAML
commits:
  format: conventional
version:
  tag_prefix_v: true
  components:
    epoch:
      enabled: false
      initial: 0
    major:
      enabled: true
      initial: 18
    patch:
      enabled: true
      initial: 0
    hotfix_counter:
      enabled: true
      initial: 0
branches:
  development: sandbox-18
  production: sandbox-18
  tag_on: sandbox-18
  hotfix_targets:
  - sandbox-18
hotfix:
  keyword:
  - '^hotfix(\(|:)'
  - '^[Hh]otfix/'
  - 'URGENT-PATCH'
changelog:
  mode: full
  commit_url: https://github.com/PanoraGrowth/panora-versioning-pipe-test/commit
  include_author: true
  include_commit_link: true
  include_ticket_link: false
  per_folder:
    enabled: true
    folders:
    - backend
    - frontend
    scope_matching: exact
    fallback: file_path
YAML
}

build_versioning_yml_19() {
    cat <<YAML
commits:
  format: conventional
version:
  tag_prefix_v: true
  components:
    epoch:
      enabled: false
      initial: 0
    major:
      enabled: true
      initial: 19
    patch:
      enabled: true
      initial: 0
    hotfix_counter:
      enabled: true
      initial: 0
branches:
  development: sandbox-19
  production: sandbox-19
  tag_on: sandbox-19
  hotfix_targets:
  - sandbox-19
hotfix:
  keyword:
  - "^hotfix(\\(|:)"
  - "^[Hh]otfix/"
  - "URGENT-PATCH"
changelog:
  mode: full
  commit_url: https://github.com/PanoraGrowth/panora-versioning-pipe-test/commit
  include_author: true
  include_commit_link: true
  include_ticket_link: false
  per_folder:
    enabled: false
version_file:
  enabled: true
  groups:
    - name: services
      files:
        - path: services/version.yaml
      trigger_paths:
        - services/**
YAML
}

build_versioning_yml_20() {
    cat <<YAML
commits:
  format: conventional
version:
  tag_prefix_v: true
  components:
    epoch:
      enabled: false
      initial: 0
    major:
      enabled: true
      initial: 20
    patch:
      enabled: true
      initial: 0
    hotfix_counter:
      enabled: true
      initial: 0
branches:
  development: sandbox-20
  production: sandbox-20
  tag_on: sandbox-20
  hotfix_targets:
  - sandbox-20
hotfix:
  keyword:
  - "^hotfix(\\(|:)"
  - "^[Hh]otfix/"
  - "URGENT-PATCH"
changelog:
  mode: full
  commit_url: https://github.com/PanoraGrowth/panora-versioning-pipe-test/commit
  include_author: true
  include_commit_link: true
  include_ticket_link: false
  per_folder:
    enabled: false
version_file:
  enabled: true
  groups:
    - name: services
      files:
        - path: services/version.yaml
      trigger_paths:
        - services/**
YAML
}

build_versioning_yml_26() {
    cat <<YAML
commits:
  format: conventional
version:
  tag_prefix_v: true
  components:
    epoch:
      enabled: false
      initial: 0
    major:
      enabled: true
      initial: 26
    patch:
      enabled: true
      initial: 0
    hotfix_counter:
      enabled: true
      initial: 0
branches:
  development: sandbox-26
  production: sandbox-26
  tag_on: sandbox-26
  hotfix_targets:
  - sandbox-26
hotfix:
  keyword:
  - "^hotfix(\\(|:)"
  - "^[Hh]otfix/"
  - "URGENT-PATCH"
changelog:
  mode: full
  commit_url: https://github.com/PanoraGrowth/panora-versioning-pipe-test/commit
  include_author: true
  include_commit_link: true
  include_ticket_link: false
  per_folder:
    enabled: false
YAML
}

build_versioning_yml_27() {
    cat <<YAML
commits:
  format: conventional
version:
  tag_prefix_v: true
  components:
    epoch:
      enabled: true
      initial: 1
    major:
      enabled: true
      initial: 27
    patch:
      enabled: true
      initial: 0
    hotfix_counter:
      enabled: true
      initial: 0
branches:
  development: sandbox-27
  production: sandbox-27
  tag_on: sandbox-27
  hotfix_targets:
  - sandbox-27
hotfix:
  keyword:
  - "^hotfix(\\(|:)"
  - "^[Hh]otfix/"
  - "URGENT-PATCH"
changelog:
  mode: full
  commit_url: https://github.com/PanoraGrowth/panora-versioning-pipe-test/commit
  include_author: true
  include_commit_link: true
  include_ticket_link: false
  per_folder:
    enabled: false
YAML
}

build_versioning_yml_29() {
    cat <<YAML
commits:
  format: conventional
version:
  tag_prefix_v: true
  components:
    epoch:
      enabled: false
      initial: 0
    major:
      enabled: true
      initial: 29
    patch:
      enabled: true
      initial: 0
    hotfix_counter:
      enabled: true
      initial: 0
branches:
  development: sandbox-29
  production: sandbox-29
  tag_on: sandbox-29
  hotfix_targets:
  - sandbox-29
hotfix:
  keyword:
  - "^hotfix(\\(|:)"
  - "^[Hh]otfix/"
  - "URGENT-PATCH"
changelog:
  mode: full
  commit_url: https://github.com/PanoraGrowth/panora-versioning-pipe-test/commit
  include_author: true
  include_commit_link: true
  include_ticket_link: false
  per_folder:
    enabled: false
YAML
}

build_versioning_yml_28() {
    cat <<YAML
commits:
  format: conventional
version:
  tag_prefix_v: true
  components:
    epoch:
      enabled: false
      initial: 0
    major:
      enabled: true
      initial: 28
    patch:
      enabled: true
      initial: 0
    hotfix_counter:
      enabled: true
      initial: 0
branches:
  development: sandbox-28
  production: sandbox-28
  tag_on: sandbox-28
  hotfix_targets:
  - sandbox-28
hotfix:
  keyword:
  - "^hotfix(\\(|:)"
  - "^[Hh]otfix/"
  - "URGENT-PATCH"
changelog:
  mode: full
  commit_url: https://github.com/PanoraGrowth/panora-versioning-pipe-test/commit
  include_author: true
  include_commit_link: true
  include_ticket_link: false
  per_folder:
    enabled: false
YAML
}

# ---------------------------------------------------------------------------
# Seed a single sandbox
# ---------------------------------------------------------------------------
seed_sandbox() {
    n="$1"  # 1..34 (numeric, no leading zero)
    branch="sandbox-$(printf '%02d' "$n")"
    log "Processing ${branch}..."

    if [ "$DRY_RUN" -eq 1 ]; then
        log "DRY-RUN: Would create/update ${branch} with major.initial=${n}"
        return 0
    fi

    # Create branch if it doesn't exist
    if ! branch_exists "$branch"; then
        log "  Creating branch ${branch} from main..."
        main_sha=$(get_main_sha)
        create_branch "$branch" "$main_sha"
    else
        log "  Branch ${branch} already exists — updating config only"
    fi

    # Build .versioning.yml
    case "$n" in
        16) yml_content=$(build_versioning_yml_16) ;;
        17) yml_content=$(build_versioning_yml_17) ;;
        18) yml_content=$(build_versioning_yml_18) ;;
        19) yml_content=$(build_versioning_yml_19) ;;
        20) yml_content=$(build_versioning_yml_20) ;;
        26) yml_content=$(build_versioning_yml_26) ;;
        27) yml_content=$(build_versioning_yml_27) ;;
        28) yml_content=$(build_versioning_yml_28) ;;
        29) yml_content=$(build_versioning_yml_29) ;;
        *)  yml_content=$(build_versioning_yml "$n") ;;
    esac

    existing_sha=$(get_file_sha "$branch" ".versioning.yml")
    log "  Committing .versioning.yml (major.initial=${n})..."
    commit_file "$branch" ".versioning.yml" "$yml_content" \
        "chore(test-setup): seed ${branch}" \
        "$existing_sha"

    # Seed additional files for sandboxes 16-20
    case "$n" in
        16) seed_sandbox_16 "$branch" ;;
        17) seed_sandbox_17 "$branch" ;;
        18) seed_sandbox_18 "$branch" ;;
        19) seed_sandbox_19 "$branch" ;;
        20) seed_sandbox_20 "$branch" ;;
        26|27|28|29|30|31|32|33|34) ;; # no additional fixtures needed
    esac

    log "  ${branch} done."
}

seed_sandbox_16() {
    branch="$1"
    readme_content="# 001-cluster-ecs
Stub directory for sandbox-16 per-folder suffix-matching tests.
"
    existing_sha=$(get_file_sha "$branch" "services/001-cluster-ecs/README.md")
    if [ -z "$existing_sha" ]; then
        log "  Seeding services/001-cluster-ecs/README.md..."
        commit_file "$branch" "services/001-cluster-ecs/README.md" "$readme_content" \
            "chore(test-setup): seed sandbox-16 fixtures" ""
    fi
}

seed_sandbox_17() {
    branch="$1"
    backend_readme="# backend
Stub directory for sandbox-17 per-folder fallback-file-path tests.
"
    frontend_readme="# frontend
Stub directory for sandbox-17 per-folder fallback-file-path tests.
"
    existing_backend=$(get_file_sha "$branch" "backend/README.md")
    if [ -z "$existing_backend" ]; then
        log "  Seeding backend/README.md..."
        commit_file "$branch" "backend/README.md" "$backend_readme" \
            "chore(test-setup): seed sandbox-17 fixtures" ""
    fi
    existing_frontend=$(get_file_sha "$branch" "frontend/README.md")
    if [ -z "$existing_frontend" ]; then
        log "  Seeding frontend/README.md..."
        commit_file "$branch" "frontend/README.md" "$frontend_readme" \
            "chore(test-setup): seed sandbox-17 fixtures" ""
    fi
}

seed_sandbox_18() {
    branch="$1"
    backend_readme="# backend
Stub directory for sandbox-18 per-folder multi-folder-write tests.
"
    frontend_readme="# frontend
Stub directory for sandbox-18 per-folder multi-folder-write tests.
"
    existing_backend=$(get_file_sha "$branch" "backend/README.md")
    if [ -z "$existing_backend" ]; then
        log "  Seeding backend/README.md..."
        commit_file "$branch" "backend/README.md" "$backend_readme" \
            "chore(test-setup): seed sandbox-18 fixtures" ""
    fi
    existing_frontend=$(get_file_sha "$branch" "frontend/README.md")
    if [ -z "$existing_frontend" ]; then
        log "  Seeding frontend/README.md..."
        commit_file "$branch" "frontend/README.md" "$frontend_readme" \
            "chore(test-setup): seed sandbox-18 fixtures" ""
    fi
}

seed_sandbox_19() {
    branch="$1"
    version_yaml="version: \"0.0.0\"
"
    services_readme="# services
Stub directory for sandbox-19 version-file-groups tests.
"
    main_tf="# placeholder services entrypoint
"
    existing_ver=$(get_file_sha "$branch" "services/version.yaml")
    if [ -z "$existing_ver" ]; then
        log "  Seeding services/version.yaml..."
        commit_file "$branch" "services/version.yaml" "$version_yaml" \
            "chore(test-setup): seed sandbox-19 fixtures" ""
    fi
    existing_readme=$(get_file_sha "$branch" "services/README.md")
    if [ -z "$existing_readme" ]; then
        log "  Seeding services/README.md..."
        commit_file "$branch" "services/README.md" "$services_readme" \
            "chore(test-setup): seed sandbox-19 fixtures" ""
    fi
    existing_tf=$(get_file_sha "$branch" "services/main.tf")
    if [ -z "$existing_tf" ]; then
        log "  Seeding services/main.tf..."
        commit_file "$branch" "services/main.tf" "$main_tf" \
            "chore(test-setup): seed sandbox-19 fixtures" ""
    fi
}

seed_sandbox_20() {
    branch="$1"
    version_yaml="version: \"0.0.0\"
"
    services_readme="# services
Stub directory for sandbox-20 version-file-groups tests.
"
    infra_readme="# infrastructure
Stub directory for sandbox-20 version-file-groups no-match tests.
"
    existing_ver=$(get_file_sha "$branch" "services/version.yaml")
    if [ -z "$existing_ver" ]; then
        log "  Seeding services/version.yaml..."
        commit_file "$branch" "services/version.yaml" "$version_yaml" \
            "chore(test-setup): seed sandbox-20 fixtures" ""
    fi
    existing_readme=$(get_file_sha "$branch" "services/README.md")
    if [ -z "$existing_readme" ]; then
        log "  Seeding services/README.md..."
        commit_file "$branch" "services/README.md" "$services_readme" \
            "chore(test-setup): seed sandbox-20 fixtures" ""
    fi
    existing_infra=$(get_file_sha "$branch" "infrastructure/README.md")
    if [ -z "$existing_infra" ]; then
        log "  Seeding infrastructure/README.md..."
        commit_file "$branch" "infrastructure/README.md" "$infra_readme" \
            "chore(test-setup): seed sandbox-20 fixtures" ""
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    if [ -n "$SINGLE_SANDBOX" ]; then
        n=$((10#$SINGLE_SANDBOX))   # strip leading zero
        if [ "$n" -lt 1 ] || [ "$n" -gt 34 ]; then
            die "Sandbox number must be between 1 and 34, got: ${SINGLE_SANDBOX}"
        fi
        seed_sandbox "$n"
    else
        i=1
        while [ "$i" -le 34 ]; do
            seed_sandbox "$i"
            i=$((i + 1))
        done
    fi
    log "All done."
}

main
