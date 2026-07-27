#!/usr/bin/env bash
# Test runner for the custom-update skill.
# Discovers and runs all tests in the tests/ directory.
# Usage: bash tests/run-tests.sh [--unit|--integration|--regression] [--verbose] [--skip-integration]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

VERBOSE=false
SKIP_INTEGRATION=false
TEST_TYPE_FILTER=""

usage() {
    echo "Usage: $0 [--unit|--integration|--regression] [--verbose] [--skip-integration]"
    echo ""
    echo "Options:"
    echo "  --unit                  Run unit tests only"
    echo "  --integration           Run integration tests only"
    echo "  --regression            Run regression tests only"
    echo "  --verbose               Show detailed output"
    echo "  --skip-integration      Skip integration tests (no live Hermes required)"
    echo ""
    echo "If no filter is specified, all test types are run."
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --unit)
            TEST_TYPE_FILTER="unit"
            shift
            ;;
        --integration)
            TEST_TYPE_FILTER="integration"
            shift
            ;;
        --regression)
            TEST_TYPE_FILTER="regression"
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --skip-integration)
            SKIP_INTEGRATION=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

echo "══════════════════════════════════════════════════════"
echo "  custom-update Test Suite"
echo "══════════════════════════════════════════════════════"
echo "  Project root: $PROJECT_ROOT"
echo "  Filter:       ${TEST_TYPE_FILTER:-all}"
echo "  Verbose:      $VERBOSE"
echo "  Skip integration: $SKIP_INTEGRATION"
echo ""

# Discover test files
UNIT_TESTS=()
INTEGRATION_TESTS=()
REGRESSION_TESTS=()

while IFS= read -r -d '' f; do
    UNIT_TESTS+=("$f")
done < <(find "$SCRIPT_DIR/unit" -name 'test-*.sh' -print0 2>/dev/null | sort -z)

while IFS= read -r -d '' f; do
    INTEGRATION_TESTS+=("$f")
done < <(find "$SCRIPT_DIR/integration" -name 'test-*.sh' -print0 2>/dev/null | sort -z)

while IFS= read -r -d '' f; do
    REGRESSION_TESTS+=("$f")
done < <(find "$SCRIPT_DIR/regression" -name 'test-*.sh' -print0 2>/dev/null | sort -z)

passed=0
failed=0
skipped=0
failed_names=()

run_test() {
    local test_name="$1"
    local test_script="$2"
    local test_type="$3"

    if [[ "$VERBOSE" == "true" ]]; then
        echo "  Running: $test_name ($test_type)..."
    fi

    local output
    output=$("$test_script" 2>&1) && {
        if [[ "$VERBOSE" == "true" ]]; then
            echo "  PASS: $test_name"
        fi
        passed=$((passed + 1))
    } || {
        echo "  FAIL: $test_name (exit code: $?)"
        if [[ "$VERBOSE" == "true" ]]; then
            echo "$output" | tail -3
        fi
        failed=$((failed + 1))
        failed_names+=("$test_name")
    }
}

should_run() {
    local test_type="$1"
    if [[ -n "$TEST_TYPE_FILTER" ]]; then
        [[ "$TEST_TYPE_FILTER" == "$test_type" ]]
    else
        true
    fi
}

# Unit tests
if should_run "unit"; then
    echo "══════════════════════════════════════════════════════"
    echo "  Unit Tests"
    echo "══════════════════════════════════════════════════════"
    for test_script in "${UNIT_TESTS[@]}"; do
        test_name="$(basename "$test_script" .sh)"
        run_test "$test_name" "$test_script" "unit"
    done
fi

# Integration tests
if [[ "$SKIP_INTEGRATION" == "false" ]] && should_run "integration"; then
    # Check if a live Hermes installation is available
    if command -v hermes &>/dev/null || [[ -n "${HERMES_ROOT:-}" ]] || [[ -d "$HOME/.hermes" ]]; then
        echo "══════════════════════════════════════════════════════"
        echo "  Integration Tests"
        echo "══════════════════════════════════════════════════════"
        for test_script in "${INTEGRATION_TESTS[@]}"; do
            test_name="$(basename "$test_script" .sh)"
            run_test "$test_name" "$test_script" "integration"
        done
    else
        echo "══════════════════════════════════════════════════════"
        echo "  Integration Tests (SKIPPED)"
        echo "══════════════════════════════════════════════════════"
        echo "  No live Hermes installation detected."
        echo "  Run with --skip-integration to suppress this message,"
        echo "  or set HERMES_ROOT or install Hermes to enable integration tests."
        skipped=${#INTEGRATION_TESTS[@]}
    fi
elif [[ "$SKIP_INTEGRATION" == "true" ]] && should_run "integration"; then
    echo "══════════════════════════════════════════════════════"
    echo "  Integration Tests (SKIPPED by --skip-integration)"
    echo "══════════════════════════════════════════════════════"
    skipped=${#INTEGRATION_TESTS[@]}
fi

# Regression tests
if should_run "regression"; then
    echo "══════════════════════════════════════════════════════"
    echo "  Regression Tests"
    echo "══════════════════════════════════════════════════════"
    for test_script in "${REGRESSION_TESTS[@]}"; do
        test_name="$(basename "$test_script" .sh)"
        run_test "$test_name" "$test_script" "regression"
    done
fi

# Summary
echo ""
echo "══════════════════════════════════════════════════════"
echo "  Test Summary"
echo "══════════════════════════════════════════════════════"
total=$((passed + failed + skipped))
echo "  Total:   $total"
echo "  Passed:  $passed"
echo "  Failed:  $failed"
echo "  Skipped: $skipped"
echo ""

if [[ $failed -gt 0 ]]; then
    echo "Failed tests:"
    for name in "${failed_names[@]}"; do
        echo "  - $name"
    done
    echo ""
    echo "NOTE: Integration tests require a live Hermes installation"
    echo "(set HERMES_ROOT or install Hermes to enable them)."
    exit 1
else
    echo "All tests passed."
    exit 0
fi