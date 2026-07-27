#!/usr/bin/env bash
# Test runner for the custom-update skill.
# Discovers and runs all tests in the tests/ directory.
# Usage: bash tests/run-tests.sh [--unit|--integration|--regression] [--verbose] [--no-cleanup]
# If no filter is given, runs the full suite.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$SCRIPT_DIR"
PROJECT_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

# Defaults
TEST_FILTER="all"
VERBOSE=false
NO_CLEANUP=false
PARALLEL=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TOTAL=0
PASSED=0
FAILED=0
SKIPPED=0
FAILED_TESTS=""

# Parse arguments.
while [[ $# -gt 0 ]]; do
    case "$1" in
        --unit)         TEST_FILTER="unit"; shift ;;
        --integration)  TEST_FILTER="integration"; shift ;;
        --regression)   TEST_FILTER="regression"; shift ;;
        --verbose|-v)   VERBOSE=true; shift ;;
        --no-cleanup)   NO_CLEANUP=true; shift ;;
        --parallel|-p)  PARALLEL=true; shift ;;
        --help|-h)
            echo "Usage: run-tests.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --unit         Run only unit tests"
            echo "  --integration  Run only integration tests"
            echo "  --regression   Run only regression tests"
            echo "  -v, --verbose  Show test output"
            echo "  --no-cleanup   Keep test artifacts"
            echo "  -p, --parallel Run tests in parallel (not yet implemented)"
            echo "  -h, --help     Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Print a header.
print_header() {
    echo ""
    echo "══════════════════════════════════════════════════════"
    echo "  $1"
    echo "══════════════════════════════════════════════════════"
}

# Print a test result line.
print_result() {
    local name="$1"
    local status="$2"
    local msg="${3:-}"

    case "$status" in
        PASS)
            printf '  ${GREEN}✓ PASS${NC}  %s\n' "$name"
            PASSED=$((PASSED + 1))
            ;;
        FAIL)
            printf '  ${RED}✗ FAIL${NC}  %s\n' "$name"
            FAILED=$((FAILED + 1))
            FAILED_TESTS="${FAILED_TESTS}${name}: ${msg}\n"
            ;;
        SKIP)
            printf '  ${YELLOW}⊘ SKIP${NC}  %s\n' "$name"
            SKIPPED=$((SKIPPED + 1))
            ;;
    esac
    TOTAL=$((TOTAL + 1))
}

# Run a single test script.
# Usage: run_test <test_type> <test_name> <test_script_path>
run_test() {
    local test_type="$1"
    local test_name="$2"
    local test_script="$3"

    if [[ "$TEST_FILTER" != "all" && "$TEST_FILTER" != "$test_type" ]]; then
        return 0
    fi

    if [[ ! -x "$test_script" ]]; then
        print_result "$test_name" "SKIP" "not executable"
        return 0
    fi

    if [[ "$VERBOSE" == "true" ]]; then
        echo "  Running: $test_name ($test_type)..." >&2
        local output
        output=$("$test_script" 2>&1) && {
            print_result "$test_name" "PASS"
        } || {
            local rc=$?
            print_result "$test_name" "FAIL" "exit code $rc"
            if [[ "$VERBOSE" == "true" ]]; then
                echo "$output" | sed 's/^/    /' >&2
            fi
        }
    else
        if "$test_script" >/dev/null 2>&1; then
            print_result "$test_name" "PASS"
        else
            local rc=$?
            print_result "$test_name" "FAIL" "exit code $rc"
        fi
    fi
}

# Discover and run all tests.
main() {
    print_header "custom-update Test Suite"
    echo "  Project root: $PROJECT_ROOT"
    echo "  Filter:       $TEST_FILTER"
    echo "  Verbose:      $VERBOSE"
    echo ""

    local test_dir=""
    local test_type=""

    # Unit tests.
    if [[ "$TEST_FILTER" == "all" || "$TEST_FILTER" == "unit" ]]; then
        test_dir="$TESTS_DIR/unit"
        test_type="unit"
        if [[ -d "$test_dir" ]]; then
            print_header "Unit Tests"
            for test_script in "$test_dir"/*.sh; do
                [[ -f "$test_script" ]] || continue
                local test_name
                test_name=$(basename "$test_script" .sh)
                run_test "$test_type" "$test_name" "$test_script"
            done
        fi
    fi

    # Integration tests.
    if [[ "$TEST_FILTER" == "all" || "$TEST_FILTER" == "integration" ]]; then
        test_dir="$TESTS_DIR/integration"
        test_type="integration"
        if [[ -d "$test_dir" ]]; then
            print_header "Integration Tests"
            for test_script in "$test_dir"/*.sh; do
                [[ -f "$test_script" ]] || continue
                local test_name
                test_name=$(basename "$test_script" .sh)
                run_test "$test_type" "$test_name" "$test_script"
            done
        fi
    fi

    # Regression tests.
    if [[ "$TEST_FILTER" == "all" || "$TEST_FILTER" == "regression" ]]; then
        test_dir="$TESTS_DIR/regression"
        test_type="regression"
        if [[ -d "$test_dir" ]]; then
            print_header "Regression Tests"
            for test_script in "$test_dir"/*.sh; do
                [[ -f "$test_script" ]] || continue
                local test_name
                test_name=$(basename "$test_script" .sh)
                run_test "$test_type" "$test_name" "$test_script"
            done
        fi
    fi

    # Summary.
    print_header "Test Summary"
    echo "  Total:   $TOTAL"
    printf "  ${GREEN}Passed:  %s${NC}\n" "$PASSED"
    printf "  ${RED}Failed:  %s${NC}\n" "$FAILED"
    printf "  ${YELLOW}Skipped: %s${NC}\n" "$SKIPPED"
    echo ""

    if [[ -n "$FAILED_TESTS" ]]; then
        echo "Failed tests:"
        echo -e "$FAILED_TESTS" | sed 's/^/  - /'
        echo ""
    fi

    # Cleanup test artifacts unless --no-cleanup.
    if [[ "$NO_CLEANUP" != "true" ]]; then
        rm -rf "${PROJECT_ROOT}/tests/.tmp" 2>/dev/null || true
    fi

    # Exit code: fail if any test failed.
    if [[ $FAILED -gt 0 ]]; then
        exit 1
    fi

    exit 0
}

main "$@"