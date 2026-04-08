#!/usr/bin/env bash
# =============================================================================
# assertions.bash — custom assertion helpers for bats tests
#
# Provides:
#   assert_equals <expected> <actual> [message]
#   assert_output_matches <regex> [message]
#   assert_empty <value> [message]
# =============================================================================

# Assert two values are equal
# Usage: assert_equals "expected" "$actual" "optional message"
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-"Values should be equal"}"

    if [ "$expected" != "$actual" ]; then
        echo "FAIL: $message" >&2
        echo "  expected: '$expected'" >&2
        echo "  actual:   '$actual'" >&2
        return 1
    fi
}

# Assert $output matches an extended regex pattern
# Uses bats $output variable (set by 'run' command)
# Usage: run some_function; assert_output_matches "^[0-9]+$" "should be numeric"
assert_output_matches() {
    local regex="$1"
    local message="${2:-"Output should match pattern"}"

    if ! [[ "$output" =~ $regex ]]; then
        echo "FAIL: $message" >&2
        echo "  pattern: '$regex'" >&2
        echo "  output:  '$output'" >&2
        return 1
    fi
}

# Assert a value is empty
# Usage: assert_empty "$result" "should return empty string"
assert_empty() {
    local value="$1"
    local message="${2:-"Value should be empty"}"

    if [ -n "$value" ]; then
        echo "FAIL: $message" >&2
        echo "  expected: (empty)" >&2
        echo "  actual:   '$value'" >&2
        return 1
    fi
}
