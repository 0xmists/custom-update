#!/usr/bin/env bash
# Backup verifier for the custom-update skill.
# Verifies backup integrity after creation.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/logging.sh"
source "$SCRIPT_DIR/bundle-manager.sh"
source "$SCRIPT_DIR/patch-manager.sh"

# Verify a complete backup.
# Usage: verify_backup <backup_dir> [base_ref]
# Returns: 0 if all checks pass, 1 if any fail.
verify_backup() {
    local backup_dir="$1"
    local base_ref="${2:-}"
    local all_passed=0

    log_info "Verifying backup: $backup_dir"

    # 1. Verify manifest exists
    if [[ ! -f "$backup_dir/manifest.json" ]]; then
        log_error "Verification failed: manifest.json not found"
        return 1
    fi
    log_info "  ✓ Manifest exists"

    # 2. Verify bundle
    local bundle_path="$backup_dir/backup.bundle"
    if [[ -f "$bundle_path" ]]; then
        if bundle_verify "$bundle_path"; then
            log_info "  ✓ Bundle verified"
        else
            log_error "  ✗ Bundle verification failed"
            all_passed=1
        fi
    else
        log_error "  ✗ Bundle file not found"
        all_passed=1
    fi

    # 3. Verify patches
    local patch_dir="$backup_dir/patches"
    if [[ -d "$patch_dir" ]]; then
        if patch_verify "$patch_dir" "$base_ref"; then
            log_info "  ✓ Patches verified"
        else
            log_error "  ✗ Patch verification failed"
            all_passed=1
        fi
    else
        log_error "  ✗ Patches directory not found"
        all_passed=1
    fi

    # 4. Verify manifest contents
    if manifest_verify "$backup_dir"; then
        log_info "  ✓ Manifest contents valid"
    else
        log_error "  ✗ Manifest contents invalid"
        all_passed=1
    fi

    # Update manifest verification status
    local bundle_ok="true"
    local patches_ok="true"
    if [[ $all_passed -ne 0 ]]; then
        bundle_ok="false"
        patches_ok="false"
    fi

    source "$SCRIPT_DIR/manifest.sh"
    manifest_update_verification "$backup_dir" \
        $([[ $all_passed -eq 0 ]] && echo "verified" || echo "failed") \
        "$bundle_ok" "$patches_ok"

    if [[ $all_passed -eq 0 ]]; then
        log_success "Backup verification passed"
    else
        log_error "Backup verification failed"
    fi

    return $all_passed
}

# Verify manifest contents.
# Usage: manifest_verify <backup_dir>
# Returns: 0 if valid, 1 if invalid.
manifest_verify() {
    local backup_dir="$1"
    local manifest_path="$backup_dir/manifest.json"

    if [[ ! -f "$manifest_path" ]]; then
        return 1
    fi

    # Check required fields
    local required_fields=("backup_id" "created_at" "hermes_version" "current_commit" "patch_count" "bundle_file" "tag")
    for field in "${required_fields[@]}"; do
        if ! grep -q "\"$field\"" "$manifest_path"; then
            log_error "Manifest missing required field: $field"
            return 1
        fi
    done

    return 0
}
