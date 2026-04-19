#!/bin/sh
# shellcheck shell=ash
# =============================================================================
# run-guardrails.sh — iterate over registered guardrails, stop on first block.
#
# Runs between version calculation and tag emission (see branch-pipeline.sh).
# Each registered function probes state from /tmp/*.txt + git and returns:
#   exit 0 → pass (continue)
#   exit 1 → block emission (fail the pipeline)
#   exit 2 → warning (config override active; continue with warning logged)
#
# Adding a new guardrail = one line here + the function in guardrails.sh.
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AUTOMATIONS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../lib/common.sh
. "${AUTOMATIONS_DIR}/lib/common.sh"
# shellcheck source=../lib/config-parser.sh
. "${AUTOMATIONS_DIR}/lib/config-parser.sh"
# shellcheck source=./guardrails.sh
. "${SCRIPT_DIR}/guardrails.sh"

# Registered guardrails — one per line. Register a new function by adding its
# name here. Order is intentional: cheaper / higher-signal checks first.
GUARDRAILS="
assert_no_version_regression
"

log_section "RUNNING GUARDRAILS"

for guardrail in $GUARDRAILS; do
    [ -z "$guardrail" ] && continue

    # Run without `set -e` inside the call so exit 2 (warning) does not abort
    # the loop. Each guardrail emits its own structured log; we only react to
    # the exit code here.
    set +e
    "$guardrail"
    status=$?
    set -e

    case "$status" in
        0)
            : # pass — next guardrail
            ;;
        2)
            : # warning already logged by the guardrail, continue
            ;;
        *)
            exit_error "Guardrail failed: $guardrail"
            ;;
    esac
done

log_success "All guardrails passed"
