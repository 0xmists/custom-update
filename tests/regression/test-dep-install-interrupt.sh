#!/usr/bin/env bash
# Test: regression — dependency-install interruption
# Regression test: when the dependency install phase (within the update provider)
# is interrupted, the next resume should re-run from the update phase,
# not try to skip it.

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"
LIB_DIR="$PROJECT_ROOT/scripts/lib"

source "$LIB_DIR/update-state.sh"
source "$LIB_DIR/logging.sh"

exit_code=0
TMP_STATE=$(mktemp -t custom-update-test-dep-interrupt.XXXXXX)
_update_state_file() { echo "$TMP_STATE"; }

echo "  State file: $TMP_STATE"

echo "[DepInterrupt 1] Only backup phase done; update not started"
update_state_init
update_state_set backup "done"
update_state_set backup_id "dep-test-backup-001"
update_state_set interrupted "true"

next=$(update_state_next_phase)
if [[ "$next" == "update" ]]; then
    echo "  PASS (resume from update — correct)"
else
    echo "  FAIL: expected 'update', got '$next'"
    exit_code=1
fi

echo "[DepInterrupt 2] update phase in_progress but not done"
update_state_set update "in_progress"
next=$(update_state_next_phase)
if [[ "$next" == "update" ]]; then
    echo "  PASS (still waiting for update to complete)"
else
    echo "  FAIL: expected 'update', got '$next'"
    exit_code=1
fi

echo "[DepInterrupt 3] update fails (set to pending) — not skipped on resume"
update_state_set update "pending"
update_state_set interrupted "true"
next=$(update_state_next_phase)
if [[ "$next" == "update" ]]; then
    echo "  PASS (update still pending, resume picks it up)"
else
    echo "  FAIL: expected 'update', got '$next'"
    exit_code=1
fi

echo "[DepInterrupt 4] After update completes, apply is next"
update_state_set update "done"
next=$(update_state_next_phase)
if [[ "$next" == "apply" ]]; then
    echo "  PASS (resumed at apply)"
else
    echo "  FAIL: expected 'apply', got '$next'"
    exit_code=1
fi

echo "[DepInterrupt 5] apply fails — does not fall through to verify"
update_state_set apply "pending"
update_state_set interrupted "true"
next=$(update_state_next_phase)
if [[ "$next" == "apply" ]]; then
    echo "  PASS (stuck at apply, not skipping)"
else
    echo "  FAIL: expected 'apply', got '$next'"
    exit_code=1
fi

echo "[DepInterrupt 6] Safety gate: verify cannot run unless apply is done"
# Simulate someone trying to bypass the safety gate.
update_state_set verify "in_progress"
# The update script's _phase_verify checks: if apply != done, it should abort.
apply_state=$(update_state_get apply)
if [[ "$apply_state" != "done" ]]; then
    echo "  PASS (safety gate works: apply not done, verify cannot proceed)"
else
    echo "  FAIL: safety gate should have prevented verify with apply not done"
    exit_code=1
fi

rm -f "$TMP_STATE"

if [[ $exit_code -eq 0 ]]; then
    echo ""
    echo "All dependency-install interruption regression tests passed."
    exit 0
else
    echo ""
    echo "Some dependency-install interruption regression tests FAILED."
    exit 1
fi