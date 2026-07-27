#!/usr/bin/env bash
# Test: regression — failed update recovery
# Regression test for the previously-fixed issue where a failed update
# left the state in an inconsistent state that prevented resumption.

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"
LIB_DIR="$PROJECT_ROOT/scripts/lib"

source "$LIB_DIR/update-state.sh"
source "$LIB_DIR/logging.sh"
source "$LIB_DIR/config.sh"
source "$LIB_DIR/atomic.sh"

exit_code=0
TMP_STATE=$(mktemp -t custom-update-test-regression.XXXXXX)
_update_state_file() { echo "$TMP_STATE"; }

echo "  State file: $TMP_STATE"

echo "[Regression 1] Failed update phase is correctly marked as 'pending'"
update_state_init
update_state_set backup "done"
update_state_set update "in_progress"
update_state_set update "pending"
update_state_set interrupted "true"

state_update=$(update_state_get update)
state_interrupted=$(update_state_get interrupted)

if [[ "$state_update" == "pending" && "$state_interrupted" == "true" ]]; then
    echo "  PASS (update=pending, interrupted=true)"
else
    echo "  FAIL: state_update='$state_update' expected 'pending', state_interrupted='$state_interrupted' expected 'true'"
    exit_code=1
fi

echo "[Regression 2] update_state_next_phase returns the failed phase"
next_phase=$(update_state_next_phase)
if [[ "$next_phase" == "update" ]]; then
    echo "  PASS (resume from update phase)"
else
    echo "  FAIL: expected 'update', got '$next_phase'"
    exit_code=1
fi

echo "[Regression 3] Previous fix — backup reuse is blocked when update not done"
update_state_set backup "done"
update_state_set backup_id "prev-backup"
update_state_set backup_reused "false"

can_reuse=false
if [[ "$(update_state_get update)" != "done" ]]; then
    can_reuse=true  # Should NOT reuse backup
fi
if [[ "$can_reuse" == "true" ]]; then
    echo "  PASS (backup reuse blocked: update not done)"
else
    echo "  FAIL: backup reuse should be blocked"
    exit_code=1
fi

echo "[Regression 4] Backup reuse allowed after update completes"
update_state_set update "done"
can_reuse=false
if [[ "$(update_state_get update)" == "done" ]]; then
    can_reuse=true
fi
if [[ "$can_reuse" == "true" ]]; then
    echo "  PASS (backup reuse allowed after update completes)"
else
    echo "  FAIL: backup reuse should be allowed when update is done"
    exit_code=1
fi

echo "[Regression 5] Successful run clears state file"
update_state_init
for phase in backup update apply verify publish; do
    update_state_set "$phase" "done"
done
update_state_clear
if [[ ! -f "$TMP_STATE" ]]; then
    echo "  PASS"
else
    echo "  FAIL: state file not cleared"
    exit_code=1
fi

rm -f "$TMP_STATE"

if [[ $exit_code -eq 0 ]]; then
    echo ""
    echo "All regression tests passed."
    exit 0
else
    echo ""
    echo "Some regression tests FAILED."
    exit 1
fi