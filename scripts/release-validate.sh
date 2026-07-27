#!/usr/bin/env bash
# Release validation gate for the custom-update skill.
# Run this before any release to validate the repository state.
# Exits non-zero if any validation fails.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "══════════════════════════════════════════════════════"
echo "  custom-update Release Validation"
echo "══════════════════════════════════════════════════════"
echo ""

errors=0

# 1. Validate all shell scripts pass bash -n
echo "[1/6] Validating shell syntax (bash -n)..."
syntax_errors=0
while IFS= read -r -d '' script; do
    if ! bash -n "$script" 2>/dev/null; then
        echo "  SYNTAX ERROR: $script"
        syntax_errors=$((syntax_errors + 1))
    fi
done < <(find "$PROJECT_ROOT/scripts" -name '*.sh' -print0 2>/dev/null)
while IFS= read -r -d '' script; do
    if ! bash -n "$script" 2>/dev/null; then
        echo "  SYNTAX ERROR: $script"
        syntax_errors=$((syntax_errors + 1))
    fi
done < <(find "$PROJECT_ROOT/tests" -name '*.sh' -print0 2>/dev/null)
if [[ $syntax_errors -eq 0 ]]; then
    echo "  PASS: All shell scripts have valid syntax"
else
    echo "  FAIL: $syntax_errors script(s) have syntax errors"
    errors=$((errors + 1))
fi

# 2. Validate configuration files
echo "[2/6] Validating configuration files..."
if [[ -f "$PROJECT_ROOT/config.yaml" ]]; then
    # Basic YAML structure check
    if grep -q "^version:" "$PROJECT_ROOT/config.yaml"; then
        echo "  PASS: config.yaml is valid"
    else
        echo "  WARN: config.yaml may be missing version field"
    fi
else
    echo "  FAIL: config.yaml not found"
    errors=$((errors + 1))
fi

# 3. Validate manifests (SKILL.md has required metadata)
echo "[3/6] Validifying SKILL.md metadata..."
if [[ -f "$PROJECT_ROOT/SKILL.md" ]]; then
    required_fields=("name:" "description:" "version:" "author:")
    missing=0
    for field in "${required_fields[@]}"; do
        if ! grep -q "^$field" "$PROJECT_ROOT/SKILL.md" 2>/dev/null; then
            echo "  MISSING: $field"
            missing=$((missing + 1))
        fi
    done
    if [[ $missing -eq 0 ]]; then
        echo "  PASS: SKILL.md has all required metadata"
    else
        echo "  FAIL: SKILL.md is missing $missing field(s)"
        errors=$((errors + 1))
    fi
else
    echo "  FAIL: SKILL.md not found"
    errors=$((errors + 1))
fi

# 4. Validate backup metadata (check scripts exist)
echo "[4/6] Validating backup metadata module..."
for lib in manifest.sh backup-manager.sh; do
    if [[ -f "$PROJECT_ROOT/scripts/lib/$lib" ]]; then
        echo "  PASS: scripts/lib/$lib exists"
    else
        echo "  FAIL: scripts/lib/$lib missing"
        errors=$((errors + 1))
    fi
done

# 5. Ensure no unfinished update exists
echo "[5/6] Checking for unfinished update state..."
backup_dir="${CUSTOM_CONFIG_DIR:-${HOME:-~/.hermes}/custom-backups}"
if [[ -f "$backup_dir/.update-state" ]]; then
    echo "  WARN: Unfinished update state found at $backup_dir/.update-state"
    echo "  This is normal if an update is currently in progress."
else
    echo "  PASS: No unfinished update state found"
fi

# 6. Run the full test suite
echo "[6/6] Running full test suite..."
if [[ -x "$PROJECT_ROOT/tests/run-tests.sh" ]]; then
    if bash "$PROJECT_ROOT/tests/run-tests.sh" 2>&1 | tail -1 | grep -q "All"; then
        echo "  PASS: All tests passed"
    else
        echo "  FAIL: Some tests failed"
        errors=$((errors + 1))
    fi
else
    echo "  FAIL: Test runner not found or not executable"
    errors=$((errors + 1))
fi

# Summary
echo ""
echo "══════════════════════════════════════════════════════"
if [[ $errors -eq 0 ]]; then
    echo "  ALL CHECKS PASSED — safe to release"
    echo "══════════════════════════════════════════════════════"
    exit 0
else
    echo "  RELEASE BLOCKED: $errors validation error(s)"
    echo "  Fix all errors before releasing."
    echo "══════════════════════════════════════════════════════"
    exit 1
fi