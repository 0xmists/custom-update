#!/usr/bin/env bash
# Verify command for the custom-update skill.
# Checks the health of the Hermes installation and custom Patches.
# Can be run standalone or as part of the update workflow.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

source "$LIB_DIR/exit-codes.sh"
source "$LIB_DIR/logging.sh"
source "$LIB_DIR/git-utils.sh"
source "$LIB_DIR/hermes-adapter.sh"
source "$LIB_DIR/config.sh"
source "$LIB_DIR/repo-locator.sh"
source "$LIB_DIR/verifier.sh"
source "$LIB_DIR/update-state.sh"
source "$LIB_DIR/patch-manager.sh"
source "$LIB_DIR/manifest.sh"

# ---------------------------------------------------------------------------
# Standalone verification of Hermes installation
# ---------------------------------------------------------------------------

# Verify Hermes is healthy (standalone mode).
# Returns: 0 if healthy, non-zero otherwise.
verify_standalone() {
    local errors=0

    log_info "Verifying Hermes installation..."

    # Check 1: Hermes root exists.
    if ! hermes_resolve_root 2>/dev/null; then
        log_error "Hermes root not found"
        errors=$((errors + 1))
    else
        log_info "  ✓ Hermes root: $HERMES_ROOT"
    fi

    # Check 2: Hermes is healthy (CLI responds).
    if hermes_verify_healthy 2>/dev/null; then
        log_info "  ✓ Hermes health check passed"
    else
        log_error "  ✗ Hermes health check failed"
        errors=$((errors + 1))
    fi

    # Check 3: Git repository is clean or status is known.
    if git_is_repo 2>/dev/null; then
        local branch
        branch=$(git_current_branch 2>/dev/null) || branch="detached"
        log_info "  ✓ Git repo: branch=$branch"
    else
        log_warn "  ⚠ Not inside a Git repository"
    fi

    # Check 4: Backups exist (if any).
    local backup_dir
    backup_dir=$(config_backup_dir 2>/dev/null)
    if [[ -n "$backup_dir" ]] && [[ -d "$backup_dir" ]]; then
        local count
        count=$(find "$backup_dir" -maxdepth 1 -type d -name "[0-9]*" 2>/dev/null | wc -l)
        log_info "  ✓ Backups found: $count"
    else
        log_info "  ℹ No backups directory found"
    fi

    if [[ $errors -gt 0 ]]; then
        log_error "Verification failed with $errors error(s)"
        return "$EXIT_VERIFICATION_FAILURE"
    fi

    log_success "All verification checks passed"
    return "$EXIT_SUCCESS"
}

# Verify a specific backup.
# Usage: verify_backup <backup_id>
# Returns: 0 if backup is valid, non-zero otherwise.
verify_backup_id() {
    local backup_id="${1:-}"
    [[ -z "$backup_id" ]] && { log_error "No backup ID provided"; return 1; }

    local backup_dir
    backup_dir=$(config_backup_dir) || return 1

    local target="$backup_dir/$backup_id"
    if [[ ! -d "$target" ]]; then
        log_error "Backup not found: $backup_id"
        return "$EXIT_BACKUP_NOT_FOUND"
    fi

    log_info "Verifying backup: $backup_id"
    verify_backup "$target"
}

# ---------------------------------------------------------------------------
# Workflow verification phase (used by update.sh)
# ---------------------------------------------------------------------------

# Verify the current custom build is healthy.
# This is Phase 4 (verify) of the update workflow.
# Returns: 0 if healthy, non-zero otherwise.
_verify_custom_build() {
    log_info "=== Verifying custom build ==="

    # Run Hermes health check.
    if ! hermes_verify_healthy; then
        log_error "Hermes does not start with custom changes applied"
        return "$EXIT_GENERAL_ERROR"
    fi

    # Run doctor health checks.
    local doctor_script="$SCRIPT_DIR/doctor.sh"
    if [[ -x "$doctor_script" ]]; then
        if bash "$doctor_script" 2>&1; then
            log_success "Health checks (doctor) passed"
        else
            log_error "Health checks (doctor) failed"
            return "$EXIT_GENERAL_ERROR"
        fi
    else
        log_warn "Doctor script not found, skipping"
    fi

    return "$EXIT_SUCCESS"
}

# Main entry point.
verify_main() {
    local subcommand="${1:-standalone}"

    case "$subcommand" in
        standalone)
            verify_standalone
            ;;
        backup)
            verify_backup_id "${2:-}"
            ;;
        *)
            log_error "Unknown verify subcommand: $subcommand"
            echo "Usage: verify.sh [standalone|<backup-id>]"
            return "$EXIT_GENERAL_ERROR"
            ;;
    esac
}

verify_main "$@"