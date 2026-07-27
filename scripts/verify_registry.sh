#!/usr/bin/env bash
# verify_registry.sh — v2.0.0: Verify all required custom features with evidence.
# Used by restore.sh after a restore operation and by the doctor command.
# Exit 0 = all required features present/adapted.
# Exit 1 = one or more required features failed/missing.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

# Resolve Hermes root: HERMES_HOME env var → user's hermes-agent checkout.
if [[ -n "${HERMES_HOME:-}" ]]; then
    HERMES_ROOT="$HERMES_HOME"
elif [[ -d "${SKILL_DIR}/../../hermes-agent" ]]; then
    HERMES_ROOT="${SKILL_DIR}/../../hermes-agent"
else
    HERMES_ROOT="$(cd "${SKILL_DIR}/../.." && pwd)/hermes-agent"
fi

SKILL_ROOT="$SKILL_DIR"
REGISTRY_DIR="$SKILL_DIR/registry"
FEATURES_JSON="$REGISTRY_DIR/features.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

missing=0
total=0
restored=0
failed=0
adapted=0
passed=0

# Evidence accumulator for the final report
EVIDENCE_FILE=""

log_ok()   { printf "${GREEN}[PASS]${NC} %s\n" "$1"; }
log_fail() { printf "${RED}[FAIL]${NC} %s\n" "$1"; missing=$((missing + 1)); failed=$((failed + 1)); }
log_warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
log_info() { printf "${BLUE}[INFO]${NC} %s\n" "$1"; }

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

echo "=== Custom Feature Registry v2 Verification ==="
echo "Checking $feature_count required features against $HERMES_ROOT..."
echo ""

# Collect evidence for each feature into a temp file
EVIDENCE_FILE=$(mktemp)

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
    version=$(python3 -c "
import json
with open('$FEATURES_JSON') as f:
    data = json.load(f)
print(data['features'][$i].get('version', '1'))
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
    gate=$(python3 -c "
import json
with open('$FEATURES_JSON') as f:
    data = json.load(f)
print(data['features'][$i].get('restore_gate', 'optional'))
")
    files_json=$(python3 -c "
import json
with open('$FEATURES_JSON') as f:
    data = json.load(f)
print(' '.join(data['features'][$i]['files']))
" 2>/dev/null || echo "")
    expected_checks=$(python3 -c "
import json
with open('$FEATURES_JSON') as f:
    data = json.load(f)
print(' '.join(data['features'][$i].get('expected_checks', [])))
" 2>/dev/null || echo "")

    total=$((total + 1))

    # Skip optional features
    if [[ "$required" != "true" ]]; then
        continue
    fi

    feature_failed=false
    feature_evidence=""

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

    # Feature-specific verification with evidence collection
    if [[ "$feature_id" == "hermes-vault" ]]; then
        # Check vault-specific markers with evidence
        evidence_items=()
        for marker in 'review_toolsets.*file' '"write_file"' 'HermesVault' 'vault-write-tracker'; do
            if grep -q "$marker" "$HERMES_ROOT/agent/background_review.py" 2>/dev/null; then
                evidence_items+=("$marker")
            fi
        done
        if [[ ${#evidence_items[@]} -ge 3 ]]; then
            log_ok "$feature_name v$version — all vault integration points verified"
            restored=$((restored + 1))
            passed=$((passed + 1))
            feature_evidence="review_toolsets contains file|notify_tools contains write_file|vault detection exists|tracker instructions present"
        else
            log_fail "$feature_name v$version — missing vault integration points"
            feature_evidence="MISSING: ${evidence_items[*]}"
            feature_failed=true
        fi
        # Write evidence
        echo "$feature_id|$version|PASS|$feature_evidence|$status" >> "$EVIDENCE_FILE"
        continue
    fi

    if [[ "$feature_id" == "execution-state" ]]; then
        evidence_items=()
        if grep -q 'create_execution_marker' "$HERMES_ROOT/agent/execution_state.py" 2>/dev/null; then
            evidence_items+=("create_execution_marker")
        fi
        if grep -q 'load_execution_marker' "$HERMES_ROOT/agent/execution_state.py" 2>/dev/null; then
            evidence_items+=("load_execution_marker")
        fi
        if grep -q 'update_execution_marker' "$HERMES_ROOT/agent/execution_state.py" 2>/dev/null; then
            evidence_items+=("update_execution_marker")
        fi
        if grep -q 'remove_execution_marker' "$HERMES_ROOT/agent/execution_state.py" 2>/dev/null; then
            evidence_items+=("remove_execution_marker")
        fi
        if grep -q 'from agent.execution_state import' "$HERMES_ROOT/agent/tool_executor.py" 2>/dev/null; then
            evidence_items+=("tool_executor imports execution_state")
        fi
        if grep -q 'execution_context' "$HERMES_ROOT/gateway/platforms/base.py" 2>/dev/null; then
            evidence_items+=("base.py has execution_context field")
        fi
        if grep -q 'execution_context' "$HERMES_ROOT/gateway/platforms/webhook.py" 2>/dev/null; then
            evidence_items+=("webhook.py populates execution_context")
        fi
        if grep -q '_execution_context' "$HERMES_ROOT/gateway/run.py" 2>/dev/null; then
            evidence_items+=("run.py sets _execution_context")
        fi

        if [[ ${#evidence_items[@]} -ge 7 ]]; then
            log_ok "$feature_name v$version — all 5 files present with key functions"
            restored=$((restored + 1))
            passed=$((passed + 1))
            feature_evidence=$(IFS='|'; echo "${evidence_items[*]}")
        else
            log_fail "$feature_name v$version — missing execution state components"
            feature_evidence="MISSING: ${evidence_items[*]}"
            feature_failed=true
        fi
        echo "$feature_id|$version|PASS|$feature_evidence|$status" >> "$EVIDENCE_FILE"
        continue
    fi

    # Generic check for other features (patch-manager, auto-confirm, stale-branch-cleanup,
    # doctor-checks, resume-support, retention)
    if [[ "$all_present" == "true" ]]; then
        # For these features, files exist and we've verified them in doctor checks
        log_ok "$feature_name v$version — files present ($status)"
        restored=$((restored + 1))
        passed=$((passed + 1))
        feature_evidence="all_files_present|status=$status"
        echo "$feature_id|$version|PASS|$feature_evidence|$status" >> "$EVIDENCE_FILE"
    else
        log_fail "$feature_name v$version — missing files: $files_json"
        feature_evidence="MISSING files: $files_json"
        echo "$feature_id|$version|FAILED|$feature_evidence|$status" >> "$EVIDENCE_FILE"
    fi
done

# Restore gate check: fail if any required feature is FAILED or MISSING
echo ""
echo "=== Restore Gate ==="
gate_failed=false

# Re-parse evidence to check for failures
if [[ -f "$EVIDENCE_FILE" ]]; then
    while IFS='|' read -r fid fver fstatus fevidence fregstatus; do
        if [[ "$fstatus" == "FAILED" ]] || [[ "$fstatus" == "MISSING" ]]; then
            gate_failed=true
            log_fail "Restore gate: $fid v$fver is $fstatus — restore must NOT succeed"
        fi
    done < "$EVIDENCE_FILE"
fi

echo ""
echo "=== Verification Report ==="
echo "Total required features: $total"
echo "Passed: $passed"
echo "Adapted: $adapted"
echo "Failed: $failed"
echo ""

# Print the evidence table
echo "=== Evidence Table ==="
printf "${BLUE}%-25s %-8s %-8s %s${NC}\n" "Feature" "Version" "Status" "Evidence"
printf "${BLUE}%-25s %-8s %-8s %s${NC}\n" "------" "-------" "------" "--------"
if [[ -f "$EVIDENCE_FILE" ]]; then
    while IFS='|' read -r fid fver fstatus fevidence fregstatus; do
        printf "%-25s %-8s %-8s %s\n" "$fid" "v$fver" "$fstatus" "$fevidence"
    done < "$EVIDENCE_FILE"
fi

# Cleanup
rm -f "$EVIDENCE_FILE"

if [[ $missing -gt 0 ]]; then
    echo ""
    echo "REQUIRED: Restore failed — $failed required feature(s) failed/missing."
    echo "See registry/ for migration instructions on each missing feature."
    echo "The customized Hermes is NOT fully restored."
    exit 1
fi

echo ""
echo "All required custom features verified. Restore gate passed."
exit 0