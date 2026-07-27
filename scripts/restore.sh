#!/usr/bin/env bash
# Restore command for the custom-update skill.
# Restores from a backup using the safest available method.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

source "$LIB_DIR/exit-codes.sh"
source "$LIB_DIR/logging.sh"
source "$LIB_DIR/git-utils.sh"
source "$LIB_DIR/repo-locator.sh"
source "$LIB_DIR/config.sh"
source "$LIB_DIR/history.sh"
source "$LIB_DIR/manifest.sh"

# Find the latest backup directory.
# Returns: 0 and echoes the path, or 1 if none found.
_find_latest_backup() {
    local backup_dir
    backup_dir=$(config_backup_dir)
    if [[ ! -d "$backup_dir" ]]; then
        return 1
    fi
    # Find the most recent backup directory (by name, which includes timestamp)
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

    # Check for tag
    local backup_id
    backup_id=$(basename "$backup_dir")
    local tag_name="backup/$backup_id"
    if git_ref_exists "refs/tags/$tag_name" 2>/dev/null; then
        methods+=("tag")
    fi

    # Check for bundle
    if [[ -f "$backup_dir/backup.bundle" ]]; then
        methods+=("bundle")
    fi

    # Check for patches
    if [[ -d "$backup_dir/patches" ]]; then
        local count
        count=$(find "$backup_dir/patches" -name '*.patch' | wc -l)
        if (( count > 0 )); then
            methods+=("patches")
        fi
    fi

    echo "${methods[*]}"
}

# Restore from a Git tag.
# Usage: _restore_from_tag <backup_dir>
# Returns: 0 on success, 1 on failure.
_restore_from_tag() {
    local backup_dir="$1"
    local backup_id
    backup_id=$(basename "$backup_dir")
    local tag_name="backup/$backup_id"
    local restore_branch="restore/$backup_id"

    log_info "Restoring from tag: $tag_name"

    # Create a restore branch from the tag
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

    # Create a restore branch from the bundle
    local temp_dir
    temp_dir=$(mktemp -d)
    if git clone "$bundle_path" "$temp_dir" 2>/dev/null; then
        local bundle_commit
        bundle_commit=$(cd "$temp_dir" && git rev-parse HEAD 2>/dev/null)
        if [[ -n "$bundle_commit" ]]; then
            # Create branch from the bundle's commit
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
# Usage: _restore_from_patches <backup_dir>
# Returns: 0 on success, 1 on failure.
_restore_from_patches() {
    local backup_dir="$1"
    local patch_dir="$backup_dir/patches"

    log_info "Restoring from patches: $patch_dir"

    # Apply patches to current branch
    if git am --3way "$patch_dir"/*.patch 2>/dev/null; then
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

    # Load config
    config_load 2>/dev/null || true

    # Locate Hermes repo
    if ! locate_hermes_repo; then
        return "$EXIT_REPO_NOT_FOUND"
    fi
    cd_hermes_repo || return "$EXIT_REPO_NOT_FOUND"

    # Find backup
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

    # Detect available recovery methods
    local methods
    methods=$(_detect_recovery_methods "$backup_dir")
    if [[ -z "$methods" ]]; then
        log_error "No recovery methods available for this backup"
        return "$EXIT_RESTORE_FAILURE"
    fi

    # Display available methods and recommendation
    echo ""
    echo "Available recovery methods:"
    for method in $methods; do
        case "$method" in
            tag)    echo "  ✓ Git Tag         backup/$(basename "$backup_dir")" ;;
            bundle) echo "  ✓ Git Bundle      $backup_dir/backup.bundle" ;;
            patches) echo "  ✓ Exported Patches $backup_dir/patches/" ;;
        esac
    done

    # Recommend the safest method
    local recommended=""
    local reason=""
    for method in $methods; do
        case "$method" in
            tag)
                recommended="tag"
                reason="Fastest recovery. Will create branch 'restore/$(basename "$backup_dir")' from the backup tag."
                break
                ;;
            bundle)
                if [[ -z "$recommended" ]]; then
                    recommended="bundle"
                    reason="Most complete recovery. Works even if the current repository is destroyed."
                fi
                ;;
            patches)
                if [[ -z "$recommended" ]]; then
                    recommended="patches"
                    reason="Most flexible. Applies patches to the current branch."
                fi
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

    # Ask for confirmation
    if ! config_confirm "Proceed with restore?"; then
        log_info "Restore cancelled"
        return "$EXIT_SUCCESS"
    fi

    # Perform restore
    local result=1
    case "$recommended" in
        tag)    _restore_from_tag "$backup_dir" || result=1 ;;
        bundle) _restore_from_bundle "$backup_dir" || result=1 ;;
        patches) _restore_from_patches "$backup_dir" || result=1 ;;
    esac

    if [[ $result -eq 0 ]]; then
        log_success "Restore completed"
        history_log "restore_performed" "success" "restored from $recommended" "$(basename "$backup_dir")"
        echo ""
        echo "Current branch: $(git_current_branch 2>/dev/null || echo 'unknown')"
        echo "Current commit: $(git_current_commit_short 2>/dev/null || echo 'unknown')"
        return "$EXIT_SUCCESS"
    else
        log_error "Restore failed"
        history_log "restore_performed" "failed" "restore from $recommended failed" "$(basename "$backup_dir")"
        return "$EXIT_RESTORE_FAILURE"
    fi
}

# Run the restore command
restore_main "$@"
