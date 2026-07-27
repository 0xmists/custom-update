#!/usr/bin/env bash
# Test: manifest creation and parsing
# Verifies that the manifest module creates valid JSON manifests,
# can update verification status, and parse fields correctly.

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
LIB_DIR="$PROJECT_ROOT/scripts/lib"

source "$LIB_DIR/manifest.sh"
source "$LIB_DIR/logging.sh"
source "$LIB_DIR/atomic.sh"

TMP_DIR=$(mktemp -d -t custom-update-test-manifest.XXXXXX)
exit_code=0
echo "  Test directory: $TMP_DIR"

# Test 1: manifest_create produces valid JSON.
echo "[Test 1] manifest_create produces valid JSON"
manifest_create "$TMP_DIR" "test-backup-001" "abc123" 5 1024
if command -v jq &>/dev/null; then
    if jq empty "$TMP_DIR/manifest.json" 2>/dev/null; then
        echo "  PASS (valid JSON)"
    else
        echo "  FAIL: manifest.json is not valid JSON"
        exit_code=1
    fi
else
    if grep -q '"manifest_version"' "$TMP_DIR/manifest.json" 2>/dev/null; then
        echo "  PASS (has manifest_version field)"
    else
        echo "  FAIL: manifest.json missing expected fields"
        exit_code=1
    fi
fi

# Test 2: manifest contains required fields.
echo "[Test 2] manifest contains required fields"
manifest_path="$TMP_DIR/manifest.json"
required_fields=("backup_id" "created_at" "hermes_version" "current_commit" "patch_count" "bundle_file" "tag")
missing=0
for field in "${required_fields[@]}"; do
    if ! grep -q "\"$field\"" "$manifest_path" 2>/dev/null; then
        echo "  MISSING: $field"
        missing=$((missing + 1))
    fi
done
if [[ $missing -eq 0 ]]; then
    echo "  PASS (all required fields present)"
else
    echo "  FAIL: $missing fields missing"
    exit_code=1
fi

# Test 3: manifest_update_verification changes status to "verified".
echo "[Test 3] manifest_update_verification updates status"
manifest_update_verification "$TMP_DIR" "verified" "true" "true"
if grep -q '"status": "verified"' "$manifest_path" 2>/dev/null; then
    echo "  PASS"
else
    echo "  FAIL: status not updated to verified"
    exit_code=1
fi

# Test 4: manifest_update_tag_pushed updates tag_pushed to true.
echo "[Test 4] manifest_update_tag_pushed updates tag_pushed"
manifest_update_tag_pushed "$TMP_DIR" "true"
if grep -q '"tag_pushed": true' "$manifest_path" 2>/dev/null; then
    echo "  PASS"
else
    echo "  FAIL: tag_pushed not updated to true"
    exit_code=1
fi

# Test 5: manifest_get extracts a field value.
echo "[Test 5] manifest_get extracts field value"
backup_id=$(manifest_get "$TMP_DIR" "backup_id")
if [[ "$backup_id" == "test-backup-001" ]]; then
    echo "  PASS (backup_id=$backup_id)"
else
    echo "  FAIL: manifest_get returned '$backup_id' expected 'test-backup-001'"
    exit_code=1
fi

# Test 6: manifest_get on non-existent backup returns error.
echo "[Test 6] manifest_get on non-existent backup"
if ! manifest_get "/tmp/nonexistent-dir" "backup_id" 2>/dev/null; then
    echo "  PASS (correctly returned error)"
else
    echo "  FAIL: manifest_get should fail on non-existent directory"
    exit_code=1
fi

# Cleanup.
rm -rf "$TMP_DIR"

if [[ $exit_code -eq 0 ]]; then
    echo ""
    echo "All manifest tests passed."
    exit 0
else
    echo ""
    echo "Some manifest tests FAILED."
    exit 1
fi