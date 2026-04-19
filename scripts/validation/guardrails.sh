#!/bin/sh
# shellcheck shell=ash
# =============================================================================
# guardrails.sh — runtime invariants enforced between version calculation and
# emission. Each guardrail is a pure probe that reads state from /tmp/*.txt and
# git, then decides whether tag emission is safe.
#
# CONTRACT — every guardrail function MUST follow:
#   Input:   reads /tmp/*.txt and git state (no positional arguments)
#   Output:  exit 0 (pass) | exit 1 (block emission) | exit 2 (warning, allowed
#            by config override)
#   Logs:    one structured line to stderr, always emitted:
#              GUARDRAIL name=<name> result=<pass|blocked|warned> key=value ...
#   State:   NEVER modifies filesystem, git refs, or /tmp/*.txt files
#   Purity:  idempotent — N invocations with the same input produce the same
#            output. No retry state, no side channels.
#
# Registration: add the function name to GUARDRAILS in run-guardrails.sh.
# Logging: use guardrail_log to keep the structured format consistent.
# =============================================================================

# Emit a structured guardrail log line to stderr.
# Args: name, result, [extra key=value pairs ...]
guardrail_log() {
    local name="$1"
    local result="$2"
    shift 2
    local extras=""
    while [ $# -gt 0 ]; do
        extras="${extras} $1"
        shift
    done
    echo "GUARDRAIL name=${name} result=${result}${extras}" >&2
}

# =============================================================================
# assert_no_version_regression
# -----------------------------------------------------------------------------
# Block emission when the computed next tag does not match the expected shape
# for the declared bump_type, relative to the latest tag in the active
# namespace. This catches calculation bugs that produce a tag whose components
# are inconsistent with the bump action (e.g. bump=patch but major regressed).
#
# Rules per bump_type:
#   epoch   → next.epoch   > latest.epoch  (strict)
#   major   → next.major   > latest.major  (strict)
#             sanity: next.epoch >= latest.epoch
#   patch   → next.patch   > latest.patch  (strict)
#             sanity: next.major >= latest.major
#                     next.epoch >= latest.epoch
#   hotfix  → if same base (epoch+major+patch identical):
#                 next.hotfix_counter > latest.hotfix_counter (strict)
#             else (base changed — counter reset is legitimate):
#                 next.epoch >= latest.epoch
#                 next.major >= latest.major
#                 next.patch >= latest.patch
#                 counter free (any value)
#
# Config override: validation.allow_version_regression=true degrades any block
# to a warning and returns exit 2, letting the pipeline continue.
#
# Pass cases (no comparison possible / no emission):
#   - /tmp/next_version.txt empty (upstream early-exit)
#   - /tmp/bump_type.txt empty (no new commits)
#   - /tmp/latest_tag.txt empty (cold start or namespace upgrade)
# =============================================================================
assert_no_version_regression() {
    local name="no_version_regression"
    local next_tag latest_tag bump_type

    next_tag=$(read_state "/tmp/next_version.txt" 2>/dev/null || echo "")
    latest_tag=$(read_state "/tmp/latest_tag.txt" 2>/dev/null || echo "")
    bump_type=$(read_state "/tmp/bump_type.txt" 2>/dev/null || echo "")

    if [ -z "$next_tag" ]; then
        guardrail_log "$name" "pass" "reason=no_next_tag"
        return 0
    fi

    if [ -z "$bump_type" ]; then
        guardrail_log "$name" "pass" "reason=no_bump" "next=${next_tag}"
        return 0
    fi

    if [ -z "$latest_tag" ]; then
        guardrail_log "$name" "pass" "reason=cold_start" "next=${next_tag}" "bump=${bump_type}"
        return 0
    fi

    # Parse both tags. parse_version_components sets globals, so snapshot each
    # parse before the next one overwrites them.
    local next_ver latest_ver
    next_ver=$(parse_tag_to_version "$next_tag")
    parse_version_components "$next_ver"
    local next_e="$PARSED_EPOCH" next_m="$PARSED_MAJOR" next_p="$PARSED_PATCH" next_h="$PARSED_HOTFIX_COUNTER"

    latest_ver=$(parse_tag_to_version "$latest_tag")
    parse_version_components "$latest_ver"
    local latest_e="$PARSED_EPOCH" latest_m="$PARSED_MAJOR" latest_p="$PARSED_PATCH" latest_h="$PARSED_HOTFIX_COUNTER"

    local violation=""

    case "$bump_type" in
        epoch)
            if ! [ "$next_e" -gt "$latest_e" ] 2>/dev/null; then
                violation="epoch_not_incremented"
            fi
            ;;
        major)
            if ! [ "$next_m" -gt "$latest_m" ] 2>/dev/null; then
                violation="major_not_incremented"
            elif ! [ "$next_e" -ge "$latest_e" ] 2>/dev/null; then
                violation="epoch_regressed"
            fi
            ;;
        patch)
            if ! [ "$next_p" -gt "$latest_p" ] 2>/dev/null; then
                violation="patch_not_incremented"
            elif ! [ "$next_m" -ge "$latest_m" ] 2>/dev/null; then
                violation="major_regressed"
            elif ! [ "$next_e" -ge "$latest_e" ] 2>/dev/null; then
                violation="epoch_regressed"
            fi
            ;;
        hotfix)
            # Same base → counter must strictly increment.
            # Base changed → every base component must be >= latest (counter free).
            if [ "$next_e" = "$latest_e" ] && [ "$next_m" = "$latest_m" ] && [ "$next_p" = "$latest_p" ]; then
                if ! [ "$next_h" -gt "$latest_h" ] 2>/dev/null; then
                    violation="hotfix_counter_not_incremented"
                fi
            else
                # Tuple comparison: (epoch, major, patch) must be >= latest as a
                # whole. A higher-order component incrementing makes the tuple
                # greater regardless of what lower-order components do (e.g. patch
                # resets to 0 when major bumps — that is valid, not a regression).
                if [ "$next_e" -gt "$latest_e" ] 2>/dev/null; then
                    : # epoch increased → entire base is greater, always valid
                elif ! [ "$next_e" -ge "$latest_e" ] 2>/dev/null; then
                    violation="epoch_regressed"
                elif [ "$next_m" -gt "$latest_m" ] 2>/dev/null; then
                    : # same epoch, major increased → valid regardless of patch
                elif ! [ "$next_m" -ge "$latest_m" ] 2>/dev/null; then
                    violation="major_regressed"
                elif ! [ "$next_p" -ge "$latest_p" ] 2>/dev/null; then
                    violation="patch_regressed"
                fi
            fi
            ;;
        *)
            # Unknown bump_type — don't crash the pipeline, flag as pass with
            # a reason. If a future bump type is introduced without updating
            # the guardrail, the log will surface it.
            guardrail_log "$name" "pass" "reason=unknown_bump" "bump=${bump_type}" "next=${next_tag}" "latest=${latest_tag}"
            return 0
            ;;
    esac

    if [ -z "$violation" ]; then
        guardrail_log "$name" "pass" "bump=${bump_type}" "next=${next_tag}" "latest=${latest_tag}"
        return 0
    fi

    if allow_version_regression; then
        guardrail_log "$name" "warned" "violation=${violation}" "bump=${bump_type}" "next=${next_tag}" "latest=${latest_tag}" "override=allow_version_regression"
        log_warn "Version regression allowed by validation.allow_version_regression=true: ${next_tag} vs ${latest_tag} (${violation})"
        return 2
    fi

    guardrail_log "$name" "blocked" "violation=${violation}" "bump=${bump_type}" "next=${next_tag}" "latest=${latest_tag}"
    log_error "Version regression blocked: computed tag ${next_tag} is inconsistent with bump=${bump_type} relative to latest tag ${latest_tag} (violation: ${violation})."
    log_error "This usually means version.components.*.initial was misconfigured or the namespace filter excluded the latest tag."
    log_error "To allow an intentional downgrade, set validation.allow_version_regression: true in .versioning.yml."
    return 1
}
