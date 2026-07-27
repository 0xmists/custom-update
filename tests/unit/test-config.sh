#!/usr/bin/env bash
# Test: config loading and defaults
# Verifies that the configuration module loads, saves, and applies defaults correctly.

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
LIB_DIR="$PROJECT_ROOT/scripts/lib"

source "$LIB_DIR/config.sh"

TMP_CFG=""
exit_code=0

# Setup: custom config file in temp dir.
TMP_CFG=$(mktemp -t custom-update-test-config.XXXXXX.yaml)
CONFIG_FILE="$TMP_CFG"
export CUSTOM_CONFIG_FILE="$TMP_CFG"

# Test 1: config_init creates the file.
echo "[Test 1] config_init creates config file"
config_init
if [[ -f "$TMP_CFG" ]]; then
    echo "  PASS"
else
    echo "  FAIL: config file not created"
    exit_code=1
fi

# Test 2: config_load reads the file and populates CONFIG vars.
echo "[Test 2] config_load populates CONFIG variables"
config_load
if [[ -n "${CONFIG_UPDATE_PROVIDER:-}" ]]; then
    echo "  PASS (update_provider=$CONFIG_UPDATE_PROVIDER)"
else
    echo "  FAIL: CONFIG_UPDATE_PROVIDER not set"
    exit_code=1
fi

# Test 3: config_save writes to file.
echo "[Test 3] config_save writes to file"
CONFIG_MAX_BACKUPS=5
CONFIG_AUTO_CLEANUP=false
config_save
if grep -q "max_backups: 5" "$TMP_CFG" 2>/dev/null; then
    echo "  PASS"
else
    echo "  FAIL: max_backups=5 not found in saved config"
    exit_code=1
fi

# Test 4: config_backup_dir returns expanded path.
echo "[Test 4] config_backup_dir returns expanded path"
CONFIG_BACKUP_DIR="~/.hermes/custom-backups"
backup_dir=$(config_backup_dir)
if [[ -n "$backup_dir" && "$backup_dir" != *"~"* ]]; then
    echo "  PASS ($backup_dir)"
else
    echo "  FAIL: backup_dir not expanded or empty"
    exit_code=1
fi

# Test 5: config_confirm_required returns correct value.
echo "[Test 5] config_confirm_required"
CONFIG_CONFIRM_DESTRUCTIVE=true
if config_confirm_required; then
    echo "  PASS (confirm required when true)"
else
    echo "  FAIL: confirm_required returned false when set to true"
    exit_code=1
fi

CONFIG_CONFIRM_DESTRUCTIVE=false
if ! config_confirm_required; then
    echo "  PASS (confirm not required when false)"
else
    echo "  FAIL: confirm_required returned true when set to false"
    exit_code=1
fi

# Test 6: config_confirm returns true for 'y' input.
echo "[Test 6] config_confirm with 'y' input"
CONFIG_CONFIRM_DESTRUCTIVE=true
echo "y" | config_confirm "Proceed?" >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
    echo "  PASS"
else
    echo "  FAIL: config_confirm returned false for 'y'"
    exit_code=1
fi

# Test 7: config_confirm returns false for 'n' input.
echo "[Test 7] config_confirm with 'n' input"
echo "n" | config_confirm "Proceed?" >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
    echo "  PASS"
else
    echo "  FAIL: config_confirm returned true for 'n'"
    exit_code=1
fi

# Test 8: config_load handles missing file gracefully.
echo "[Test 8] config_load handles missing file"
rm -f "$TMP_CFG"
config_load
echo "  PASS (no crash with missing file)"

# Cleanup.
rm -f "$TMP_CFG"

if [[ $exit_code -eq 0 ]]; then
    echo ""
    echo "All config tests passed."
    exit 0
else
    echo ""
    echo "Some config tests FAILED."
    exit 1
fi