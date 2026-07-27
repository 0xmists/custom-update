#!/usr/bin/env bash
# Apply command for the custom-update skill.
# Reapplies custom patches to the updated Hermes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

source "$LIB_DIR/exit-codes.sh"
source "$LIB_DIR/logging.sh"
source "$LIB_DIR/git-utils.sh"
source "$LIB_DIR/repo-locator.sh"
source "$LIB_DIR/config.sh"
source "$LIB_DIR/history.sh"
source "$LIB_DIR/patch-manager.sh"

# Find the latest verified backup.
_find_latest_backup() {
    local backup_dir
    backup_dir=$(config_backup_dir)

    if [[ ! -d "$backup_dir" ]]; then
        return 1
    fi

    # Find the most recent backup with a verified manifest
    local latest=""
    local latest_time=0

    for dir in "$backup_dir"/*/; do
        [[ -d "$dir" ]] || continue
        local manifest="$dir/manifest.json"
        [[ -f "$manifest" ]] || continue

        # Check if verified
        if grep -q '"status": "verified"' "$manifest" 2>/dev/null; then
            local created
            created=$(grep '"created_at"' "$manifest" | sed 's/.*: *"//;s/".*//')
            local timestamp
            timestamp=$(date -d "$created" +%s 2>/dev/null || echo 0)
            if (( timestamp > latest_time )); then
                latest_time=$timestamp
                latest="$dir"
            fi
        fi
    done

    if [[ -n "$latest" ]]; then
        echo "$latest"
        return 0
    fi

    # Fallback: find any backup with patches
    for dir in "$backup_dir"/*/; do
        [[ -d "$dir/patches" ]] && [[ -n "$(ls "$dir/patches/"*.patch 2>/dev/null)" ]] && echo "$dir" && return 0
    done

    return 1
}

# Main apply function.
apply_main() {
    # Load config
    config_load 2>/dev/null || true

    # Locate Hermes repo
    if ! locate_hermes_repo; then
        return "$EXIT_REPO_NOT_FOUND"
    fi
    cd_hermes_repo || return "$EXIT_REPO_NOT_FOUND"

    # Find latest backup
    local backup_dir
    backup_dir=$(_find_latest_backup)
    if [[ -z "$backup_dir" ]]; then
        log_error "No verified backup found. Run 'hermes custom backup' first."
        return "$EXIT_BACKUP_NOT_FOUND"
    fi

    log_info "Using backup: $(basename "$backup_dir")"

    # Verify patches
    local patch_dir="$backup_dir/patches"
    if [[ ! -d "$patch_dir" ]] || [[ -z "$(ls "$patch_dir/"*.patch 2>/dev/null)" ]]; then
        log_error "No patches found in backup"
        return "$EXIT_BACKUP_NOT_FOUND"
    fi

    # Check working tree is clean
    if ! git_working_tree_clean; then
        log_warn "Working tree is not clean. Stashing changes..."
        git_stash_changes "pre-apply-$(date +%Y%m%d-%H%M)"
    fi

    # Enable rerere if configured
    if [[ "${CONFIG_ENABLE_RERERE:-true}" == "true" ]]; then
        git config rerere.enabled true 2>/dev/null || true
    fi

    # Apply patches
    local patch_files
    patch_files=$(patch_list "$patch_dir")
    local total_patches
    total_patches=$(echo "$patch_files" | wc -l)
    local applied=0
    local failed=0

    log_info "Applying $total_patches patches..."

    while IFS= read -r patch; do
        [[ -f "$patch" ]] || continue
        local patch_name
        patch_name=$(basename "$patch")

        if git am --3way "$patch" 2>/dev/null; then
            applied=$((applied + 1))
            log_info "  ✓ Applied: $patch_name"
        else
            failed=$((failed + 1))
            log_error "  ✗ Failed: $patch_name"

            # Abort and provide instructions
            git am --abort 2>/dev/null || true

            echo ""
            echo "✗ Patch application failed at patch $((applied + 1))/$total_patches"
            echo "  Failed patch: $patch_name"
            echo ""
            echo "To resolve manually:"
            echo "  1. Fix the conflicts in the listed files"
            echo "  2. Run: git add -A && git am --continue"
            echo "  3. Or to abort: git am --abort && hermes custom restore"
            echo ""
            echo "Your backup is safe. Run 'hermes custom restore' to recover."

            # Restore stashed changes
            git_stash_pop 2>/dev/null || true

            history_log "patches_applied" "failed" "$applied/$total_patches patches applied, conflict at $patch_name" "$(basename "$backup_dir")"
            return "$EXIT_PATCH_CONFLICT"
        fi
    done <<< "$patch_files"

    # Restore stashed changes
    git_stash_pop 2>/dev/null || true

    # Summary
    log_success "Custom patches applied successfully"
    echo ""
    echo "Patches: $applied/$total_patches applied"
    echo "Conflicts: $failed"
    echo "Current commit: $(git_current_commit_short) + $applied patches"

    history_log "patches_applied" "success" "$applied/$total_patches patches applied" "$(basename "$backup_dir")"

    return "$EXIT_SUCCESS"
}

# Run the apply command
apply_main "$@"
