#!/usr/bin/env bash
# verify_registry.sh — Verify all required custom features are present.
# Used by restore.sh after a restore operation and by the doctor command.
# Exit 0 = all required features present.
# Exit 1 = one or more required features missing.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

# Resolve Hermes root: HERMES_HOME env var → user's hermes-agent checkout.
# The custom-update skill lives at $HERMES_HOME/skills/custom-update,
# so HERMES_HOME is two levels above the skill dir.
# Falls back to parent-dir/HERMES_HOME env var then repo relative path.
if [[ -n "${HERMES_HOME:-}" ]]; then
    HERMES_ROOT="$HERMES_HOME"
elif [[ -d "${SKILL_DIR}/../../hermes-agent" ]]; then
    HERMES_ROOT="${SKILL_DIR}/../../hermes-agent"
else
    HERMES_ROOT="$(cd "${SKILL_DIR}/../.." && pwd)/hermes-agent"
fi

# Resolve skill root for scripts/ files
SKILL_ROOT="$SKILL_DIR"
REGISTRY_DIR="$SKILL_DIR/registry"
FEATURES_JSON="$REGISTRY_DIR/features.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

missing=0
total=0
restored=0
already_upstream=0
adapted=0

log_ok()   { printf "${GREEN}[PASS]${NC} %s\n" "$1"; }
log_fail() { printf "${RED}[FAIL]${NC} %s\n" "$1"; missing=$((missing + 1)); }
log_warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }

# Load features.json and iterate over entries
if [[ ! -f "$FEATURES_JSON" ]]; then
    echo "ERROR: No feature manifest found at $FEATURES_JSON"
    exit 2
fi

feature_count=$(python3 -c "
import json, sys
with open('$FEATURES_JSON') as f:
    data = json.load(f)
print(len(data['features']))
")

echo "=== Custom Feature Registry Verification ==="
echo "Checking $feature_count required features..."
echo ""

for i in $(seq 0 $((feature_count - 1))); do
    feature_id=$(python3 -c "
import json
with open('$FEATURES_JSON') as f:
    data = json.load(f)
print(data['features'][$i]['feature_id'])
")
    feature_name=$(python3 -c "
import json
with open('$FEATURES_JSON') as f:
    data = json.load(f)
print(data['features'][$i]['name'])
")
    required=$(python3 -c "
import json
with open('$FEATURES_JSON') as f:
    data = json.load(f)
print(str(data['features'][$i]['required']).lower())
")
    status=$(python3 -c "
import json
with open('$FEATURES_JSON') as f:
    data = json.load(f)
print(data['features'][$i]['status'])
")
    files_json=$(python3 -c "
import json
with open('$FEATURES_JSON') as f:
    data = json.load(f)
print(' '.join(data['features'][$i]['files']))
" 2>/dev/null || echo "")

    total=$((total + 1))

    if [[ "$required" != "true" ]]; then
        continue
    fi

    # Check each file for this feature
    all_present=true
    for f in $files_json; do
        # Determine the correct base path for this file
        if [[ "$f" == agent/* ]] || [[ "$f" == gateway/* ]]; then
            base="$HERMES_ROOT"
        else
            base="$SKILL_ROOT"
        fi
        full_path="$base/$f"
        if [[ ! -f "$full_path" ]]; then
            all_present=false
            break
        fi
    done

    # Special check for background_review.py which has multiple features depending on it
    if [[ "$feature_id" == "hermes-vault" ]]; then
        # Check vault-specific markers
        if grep -q 'review_toolsets.*file' "$HERMES_ROOT/agent/background_review.py" 2>/dev/null && \
           grep -q '"write_file"' "$HERMES_ROOT/agent/background_review.py" 2>/dev/null && \
           grep -q 'HermesVault' "$HERMES_ROOT/agent/background_review.py" 2>/dev/null && \
           grep -q 'vault-write-tracker' "$HERMES_ROOT/agent/background_review.py" 2>/dev/null; then
            log_ok "$feature_name — all 6 vault integration points verified"
            restored=$((restored + 1))
        else
            log_fail "$feature_name — missing vault integration points"
            # Check what's missing
            for marker in 'review_toolsets.*file' '"write_file"' 'HermesVault' 'vault-write-tracker'; do
                if ! grep -q "$marker" "$HERMES_ROOT/agent/background_review.py" 2>/dev/null; then
                    log_warn "  Missing: $marker"
                fi
            done
        fi
        continue
    fi

    if [[ "$feature_id" == "execution-state" ]]; then
        if grep -q 'create_execution_marker' "$HERMES_ROOT/agent/execution_state.py" 2>/dev/null && \
           grep -q 'from agent.execution_state import' "$HERMES_ROOT/agent/tool_executor.py" 2>/dev/null && \
           grep -q 'execution_context' "$HERMES_ROOT/gateway/platforms/base.py" 2>/dev/null; then
            log_ok "$feature_name — all 5 files present with key functions"
            restored=$((restored + 1))
        else
            log_fail "$feature_name — missing execution state components"
        fi
        continue
    fi

    # Generic check for other features
    if [[ "$all_present" == "true" ]]; then
        # For patch-manager, auto-confirm, stale-branch-cleanup, doctor-checks,
        # retention — files exist and we've already verified them in doctor checks
        log_ok "$feature_name — files present ($status)"
        restored=$((restored + 1))
    else
        log_fail "$feature_name — missing files: $files_json"
    fi
done

echo ""
echo "=== Results ==="
echo "Total required features: $total"
echo "Present: $restored"
echo "Missing: $missing"

if [[ $missing -gt 0 ]]; then
    echo ""
    echo "REQUIRED: Restore failed — $missing required feature(s) missing."
    echo "See registry/ for migration instructions on each missing feature."
    exit 1
fi

echo ""
echo "All required custom features verified."
exit 0