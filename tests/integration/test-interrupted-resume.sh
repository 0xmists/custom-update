#!/usr/bin/env bash
# Test: interruption and resume
# Verifies that an interrupted update can resume correctly.

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"
LIB_DIR="$PROJECT_ROOT/scripts/lib"

source "$LIB_DIR/update-state.sh"
source "$LIB_DIR/logging.sh"
source "$LIB_DIR/config.sh"
source "$LIB_DIR/atomic.sh"

exit_code=0
TMP_STATE=$(mktemp -t custom-update-test-resume.XXXXXX)
_update_state_file() { echo "$TMP_STATE"; }

# Setup a fake backup dir for state file.
TMP_BACKUP_DIR=$(mktemp -d -t custom-update-test-resume-state.XXXXXX)
CONFIG_BACKUP_DIR="$TMP_BACKUP_DIR"

echo "  State file: $TMP_STATE"
echo "  Backup dir: $TMP_BACKUP_DIR"

echo "[Test 1] Interrupted state is correctly recorded"
update_state_init
update_state_set backup "done"
update_state_set backup_id "interrupted-backup-001"
update_state_set update "in_progress"
update_state_set interrupted "true"

backup_state=$(update_state_get backup)
update_state=$(update_state_get update)
interrupted=$(update_state_get interrupted)
backup_id=$(update_state_get backup_id)

if [[ "$backup_state" == "done" && "$update_state" == "in_progress" && "$interrupted" == "true" && "$backup_id" == "interrupted-backup-001" ]]; then
    echo "  PASS (state saved: backup=done, update=in_progress, interrupted=true, backup_id=$backup_id)"
else
    echo "  FAIL: state mismatch"
    echo "    backup=$backup_state (expected: done)"
    echo "    update=$update_state (expected: in_progress)"
    echo "    interrupted=$interrupted (expected: true)"
    echo "    backup_id=$backup_id (expected: interrupted-backup-001)"
    exit_code=1
fi

echo "[Test 2] update_state_next_phase returns the first incomplete phase"
next_phase=$(update_state_next_phase)
if [[ "$next_phase" == "update" ]]; then
    echo "  PASS (next phase: $next_phase)"
else
    echo "  FAIL: expected 'update', got '$next_phase'"
    exit_code=1
fi

echo "[Test 3] Phase skipping works (resume from 'update')"
# Simulate: update completes successfully.
update_state_set update "done"
update_state_set apply "in_progress"

next_phase=$(update_state_next_phase)
if [[ "$next_phase" == "apply" ]]; then
    echo "  PASS (resumed at apply phase)"
else
    echo "  FAIL: expected 'apply', got '$next_phase'"
    exit_code=1
fi

echo "[Test 4] update_state_all_done returns false when not all complete"
if ! update_state_all_done; then
    echo "  PASS (correctly reports incomplete)"
else
    echo "  FAIL: should report incomplete"
    exit_code=1
fi

echo "[Test 5] Mark remaining phases done → all done"
update_state_set apply "done"
update_state_set verify "done"
update_state_set publish "done"
if update_state_all_done; then
    echo "  PASS"
else
    echo "  FAIL: should report all done"
    exit_code=1
fi

echo "[Test 6] update_state_clear removes state file"
update_state_clear
if [[ ! -f "$TMP_STATE" ]]; then
    echo "  PASS"
else
    echo "  FAIL: state file still exists after clear"
    exit_code=1
fi

# Cleanup.
rm -rf "$TMP_STATE" "$TMP_BACKUP_DIR"

if [[ $exit_code -eq 0 ]]; then
    echo ""
    echo "All resume/interruption tests passed."
    exit 0
else
    echo ""
    echo "Some resume/interruption tests FAILED."
    exit 1
fi