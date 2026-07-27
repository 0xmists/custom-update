#!/usr/bin/env bash
# Restore command for the custom-update skill.
# Restores from a backup using the safest available method.
# Uses the Hermes adapter layer for all Hermes-specific operations.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

source "$LIB_DIR/exit-codes.sh"
source "$LIB_DIR/logging.sh"
source "$LIB_DIR/git-utils.sh"
source "$LIB_DIR/hermes-adapter.sh"
source "$LIB_DIR/config.sh"
source "$LIB_DIR/repo-locator.sh"
source "$LIB_DIR/history.sh"
source "$LIB_DIR/manifest.sh"

# Locate the custom-update skill directory (parent of scripts/).
# restore.sh lives at $SKILL_DIR/scripts/restore.sh.
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REGISTRY_SCRIPT="$SKILL_DIR/scripts/verify_registry.sh"

# Find the latest backup directory.
# Returns: 0 and echoes the path, or 1 if none found.
_find_latest_backup() {
    local backup_dir
    backup_dir=$(config_backup_dir) || return 1
    [[ -d "$backup_dir" ]] || return 1

    find "$backup_dir" -maxdepth 1 -mindepth 1 -type d | sort -r | head -1
}

# Find a backup by ID.
# Usage: _find_backup <backup_id>
# Returns: 0 and echoes the path, or 1 if not found.
_find_backup() {
    local backup_id="$1"
    local backup_dir
    backup_dir=$(config_backup_dir)
    local path="$backup_dir/$backup_id"
    if [[ -d "$path" ]]; then
        echo "$path"
        return 0
    fi
    return 1
}

# Detect available recovery methods for a backup.
# Usage: _detect_recovery_methods <backup_dir>
# Echoes: space-separated list of available methods (tag bundle patches)
_detect_recovery_methods() {
    local backup_dir="$1"
    local methods=()
    local backup_id
    backup_id=$(basename "$backup_dir")
    local tag_name="backup/$backup_id"

    # Check for tag.
    if git_ref_exists "refs/tags/$tag_name" 2>/dev/null; then
        methods+=("tag")
    fi

    # Check for bundle.
    if [[ -f "$backup_dir/backup.bundle" ]]; then
        methods+=("bundle")
    fi

    # Check for patches.
    if [[ -d "$backup_dir/patches" ]]; then
        local count
        count=$(find "$backup_dir/patches" -name '*.patch' | wc -l)
        (( count > 0 )) && methods+=("patches")
    fi

    echo "${methods[*]}"
}

# Restore from a Git tag.
# Usage: _restore_from_tag <backup_dir> [--auto-confirm]
# Returns: 0 on success, 1 on failure.
_restore_from_tag() {
    local backup_dir="$1"
    local auto_confirm="${2:-}"
    local backup_id
    backup_id=$(basename "$backup_dir")
    local tag_name="backup/$backup_id"
    local restore_branch="restore/$backup_id"

    log_info "Restoring from tag: $tag_name"

    # Clean up stale restore branch from a previous failed attempt.
    if git branch "$restore_branch" 2>/dev/null; then
        log_warn "Restore branch $restore_branch already exists from a previous attempt."
        if [[ "$auto_confirm" == "--auto-confirm" ]]; then
            log_info "Auto-confirm: deleting stale branch $restore_branch"
            git branch -D "$restore_branch" 2>/dev/null || true
        else
            log_error "Delete it manually: git branch -D $restore_branch"
            return 1
        fi
    fi

    if git branch "$restore_branch" "$tag_name" 2>/dev/null; then
        git checkout "$restore_branch" 2>/dev/null
        log_info "Created and switched to branch: $restore_branch"
        return 0
    else
        log_error "Failed to create restore branch from tag"
        return 1
    fi
}

# Restore from a Git bundle.
# Usage: _restore_from_bundle <backup_dir>
# Returns: 0 on success, 1 on failure.
_restore_from_bundle() {
    local backup_dir="$1"
    local backup_id
    backup_id=$(basename "$backup_dir")
    local bundle_path="$backup_dir/backup.bundle"
    local restore_branch="restore/$backup_id"

    log_info "Restoring from bundle: $bundle_path"

    local temp_dir
    temp_dir=$(mktemp -d)
    if git clone "$bundle_path" "$temp_dir" 2>/dev/null; then
        local bundle_commit
        bundle_commit=$(cd "$temp_dir" && git rev-parse HEAD 2>/dev/null)
        if [[ -n "$bundle_commit" ]]; then
            git branch "$restore_branch" "$bundle_commit" 2>/dev/null
            git checkout "$restore_branch" 2>/dev/null
            log_info "Created and switched to branch: $restore_branch"
            rm -rf "$temp_dir"
            return 0
        fi
    fi

    rm -rf "$temp_dir"
    log_error "Failed to restore from bundle"
    return 1
}

# Restore from exported patches.
# Usage: _restore_from_patches <backup_dir> [--auto-confirm]
# Returns: 0 on success, 1 on failure.
_restore_from_patches() {
    local backup_dir="$1"
    local auto_confirm="${2:-}"
    local patch_dir="$backup_dir/patches"

    log_info "Restoring from patches: $patch_dir"

    # Filter out generated lockfile patches.
    local filtered_patches=()
    for p in "$patch_dir"/*.patch; do
        [[ -f "$p" ]] || continue
        local name
        name=$(basename "$p")
        case "$name" in
            package-lock.json.patch|yarn.lock.patch|pnpm-lock.yaml.patch)
                log_info "Skipping generated lockfile patch: $name"
                continue
                ;;
        esac
        filtered_patches+=("$p")
    done

    if (( ${#filtered_patches[@]} == 0 )); then
        log_error "No applicable patches found (all were lockfiles or none exist)"
        return 1
    fi

    # Build the argument list for git am.
    local am_args=()
    am_args+=(--3way)

    if git am "${am_args[@]}" "${filtered_patches[@]}" 2>/dev/null; then
        log_info "Patches applied successfully"
        return 0
    else
        log_error "Patch application failed"
        git am --abort 2>/dev/null || true
        return 1
    fi
}

# Main restore function.
restore_main() {
    local backup_id="${1:-}"

    # Load config.
    config_load 2>/dev/null || true
    hermes_resolve_root 2>/dev/null || true

    # Locate Hermes repo.
    if ! locate_hermes_repo; then
        return "$EXIT_REPO_NOT_FOUND"
    fi
    cd_hermes_repo || return "$EXIT_REPO_NOT_FOUND"

    # Find backup.
    local backup_dir
    if [[ -n "$backup_id" ]]; then
        backup_dir=$(_find_backup "$backup_id")
        if [[ -z "$backup_dir" ]]; then
            log_error "Backup not found: $backup_id"
            return "$EXIT_BACKUP_NOT_FOUND"
        fi
    else
        backup_dir=$(_find_latest_backup)
        if [[ -z "$backup_dir" ]]; then
            log_error "No backups found"
            return "$EXIT_BACKUP_NOT_FOUND"
        fi
    fi

    log_info "Backup: $(basename "$backup_dir")"

    # Detect available recovery methods.
    local methods
    methods=$(_detect_recovery_methods "$backup_dir")
    if [[ -z "$methods" ]]; then
        log_error "No recovery methods available for this backup"
        return "$EXIT_RESTORE_FAILURE"
    fi

    # Display available methods and recommendation.
    echo ""
    echo "Available recovery methods:"
    for method in $methods; do
        case "$method" in
            tag)    echo "  ✓ Git Tag         backup/$(basename "$backup_dir")" ;;
            bundle) echo "  ✓ Git Bundle      $backup_dir/backup.bundle" ;;
            patches) echo "  ✓ Exported Patches $backup_dir/patches/" ;;
        esac
    done

    # Recommend the safest method.
    local recommended="" reason=""
    for method in $methods; do
        case "$method" in
            tag)
                recommended="tag"
                reason="Fastest recovery. Will create branch 'restore/$(basename "$backup_dir")' from the backup tag."
                break
                ;;
            bundle)
                [[ -z "$recommended" ]] && recommended="bundle" && reason="Most complete recovery. Works even if the current repository is destroyed."
                ;;
            patches)
                [[ -z "$recommended" ]] && recommended="patches" && reason="Most flexible. Applies patches to the current branch."
                ;;
        esac
    done

    echo ""
    echo "Recommended:"
    echo "  ${recommended^}"
    echo ""
    echo "Reason:"
    echo "  $reason"
    echo ""

    # Ask for confirmation.
    if ! config_confirm "Proceed with restore?"; then
        log_info "Restore cancelled"
        return "$EXIT_SUCCESS"
    fi

    # Perform restore.
    local result=1
    case "$recommended" in
        tag)     _restore_from_tag "$backup_dir" "--auto-confirm" || result=1 ;;
        bundle)  _restore_from_bundle "$backup_dir" || result=1 ;;
        patches) _restore_from_patches "$backup_dir" "--auto-confirm" || result=1 ;;
    esac

    if [[ $result -eq 0 ]]; then
        # ── Registry Restore Gate ──
        # The restore gate is the canonical definition of a successful
        # restore. Patch application, repository state, and syntax
        # checks are supporting checks — not the final criteria.
        #
        # The workflow must never report "Restore complete" while any
        # required feature remains unresolved.
        log_info "Running Feature Registry restore gate..."

        if [[ ! -x "$REGISTRY_SCRIPT" ]]; then
            log_warn "verify_registry.sh not found or not executable at $REGISTRY_SCRIPT"
            log_warn "Cannot verify custom features — proceeding without gate check"
            gate_passed=1
        else
            # Run verify_registry.sh and capture its full output for the report.
            gate_output=$("$REGISTRY_SCRIPT" 2>&1) || gate_passed=1
        fi

        if [[ "${gate_passed:-0}" -eq 0 ]]; then
            # ── Restore gate PASSED ──
            log_success "Restore completed"
            log_success "Feature Registry restore gate PASSED"
            history_log "restore_performed" "success" "restored from $recommended" "$(basename "$backup_dir")"
            echo ""
            echo "Current branch: $(git_current_branch 2>/dev/null || echo 'unknown')"
            echo "Current commit: $(git_current_commit_short 2>/dev/null || echo 'unknown')"
            return "$EXIT_SUCCESS"
        else
            # ── Restore gate FAILED ──
            log_error "Restore gate FAILED — customized Hermes is NOT fully restored"
            echo ""
            echo "=== Restore Gate Failure Report ==="
            echo "$gate_output"
            echo ""
            echo "The customized Hermes is not yet fully restored."
            echo "Investigate the failed or missing features above, apply"
            echo "manual migrations if needed, then re-run restore."
            history_log "restore_performed" "failed" "restore gate failed for $recommended" "$(basename "$backup_dir")"
            return "$EXIT_RESTORE_FAILURE"
        fi
    else
        log_error "Restore failed (exit $result)"
        history_log "restore_performed" "failed" "restore from $recommended failed" "$(basename "$backup_dir")"
        return "$EXIT_RESTORE_FAILURE"
    fi
}

# Run the restore command.
restore_main "$@"