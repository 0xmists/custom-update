#!/usr/bin/env bash
# Test: update state machine
# Verifies that the update state tracking module correctly
# initializes, sets, gets, and clears state.

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
LIB_DIR="$PROJECT_ROOT/scripts/lib"

source "$LIB_DIR/update-state.sh"
source "$LIB_DIR/logging.sh"
source "$LIB_DIR/config.sh"
source "$LIB_DIR/atomic.sh"

# Override the state file to a temp location.
TMP_STATE=$(mktemp -t custom-update-test-state.XXXXXX)
_update_state_file() {
    echo "$TMP_STATE"
}

exit_code=0
echo "  Temp state file: $TMP_STATE"

# Test 1: update_state_init creates a clean state file.
echo "[Test 1] update_state_init creates clean state"
update_state_init
if [[ -f "$TMP_STATE" ]]; then
    echo "  PASS (state file created)"
else
    echo "  FAIL: state file not created"
    exit_code=1
fi

# Test 2: All phases start as "pending".
echo "[Test 2] All phases start as 'pending'"
update_state_load
all_pending=true
for phase in backup update apply verify publish; do
    val=$(update_state_get "$phase")
    if [[ "$val" != "pending" ]]; then
        echo "  FAIL: $phase is '$val', expected 'pending'"
        all_pending=false
        exit_code=1
    fi
done
if [[ "$all_pending" == "true" ]]; then
    echo "  PASS"
fi

# Test 3: update_state_set changes a phase status.
echo "[Test 3] update_state_set changes phase status"
update_state_set backup "done"
val=$(update_state_get backup)
if [[ "$val" == "done" ]]; then
    echo "  PASS (backup=$val)"
else
    echo "  FAIL: backup is '$val', expected 'done'"
    exit_code=1
fi

# Test 4: update_state_next_phase returns first non-done phase.
echo "[Test 4] update_state_next_phase returns first incomplete phase"
next=$(update_state_next_phase)
if [[ "$next" == "update" ]]; then
    echo "  PASS (next phase: $next)"
else
    echo "  FAIL: expected 'update', got '$next'"
    exit_code=1
fi

# Test 5: update_state_all_done returns false when not all done.
echo "[Test 5] update_state_all_done returns false when incomplete"
if ! update_state_all_done; then
    echo "  PASS (correctly reports incomplete)"
else
    echo "  FAIL: should have said incomplete"
    exit_code=1
fi

# Test 6: Mark all phases done; update_state_all_done returns true.
echo "[Test 6] All phases done → update_state_all_done returns true"
for phase in backup update apply verify publish; do
    update_state_set "$phase" "done"
done
if update_state_all_done; then
    echo "  PASS"
else
    echo "  FAIL: should have reported all done"
    exit_code=1
fi

# Test 7: update_state_clear removes the state file.
echo "[Test 7] update_state_clear removes state file"
update_state_clear
if [[ ! -f "$TMP_STATE" ]]; then
    echo "  PASS (state file removed)"
else
    echo "  FAIL: state file still exists after clear"
    exit_code=1
fi

# Test 8: update_state_load fails when no state file exists.
echo "[Test 8] update_state_load fails on missing file"
if ! update_state_load 2>/dev/null; then
    echo "  PASS (correctly returned 1)"
else
    echo "  FAIL: should have returned failure"
    exit_code=1
fi

# Test 9: backup_id and backup_reused fields work.
echo "[Test 9] backup_id and backup_reused fields"
update_state_init
update_state_set backup_id "20260727-1026-00"
update_state_set backup_reused "true"
bid=$(update_state_get backup_id)
breused=$(update_state_get backup_reused)
if [[ "$bid" == "20260727-1026-00" && "$breused" == "true" ]]; then
    echo "  PASS (backup_id=$bid, backup_reused=$breused)"
else
    echo "  FAIL: backup_id='$bid' expected '20260727-1026-00' or backup_reused='$breused' expected 'true'"
    exit_code=1
fi

# Test 10: interrupted flag.
echo "[Test 10] interrupted flag"
update_state_set interrupted "true"
int_val=$(update_state_get interrupted)
if [[ "$int_val" == "true" ]]; then
    echo "  PASS"
else
    echo "  FAIL: interrupted is '$int_val', expected 'true'"
    exit_code=1
fi

# Cleanup.
rm -f "$TMP_STATE"

if [[ $exit_code -eq 0 ]]; then
    echo ""
    echo "All update state machine tests passed."
    exit 0
else
    echo ""
    echo "Some update state machine tests FAILED."
    exit 1
fi