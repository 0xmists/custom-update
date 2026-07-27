#!/usr/bin/env bash
# Backup manager for the custom-update skill.
# Responsible for: backup creation, reuse detection, retention policy, and cleanup.
# Used by backup.sh (create / cleanup) and update.sh (reuse + post-update cleanup).

BM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$BM_DIR/logging.sh"
source "$BM_DIR/atomic.sh"
source "$BM_DIR/config.sh"
source "$BM_DIR/git-utils.sh"
source "$BM_DIR/repo-locator.sh"
source "$BM_DIR/remote-detector.sh"
source "$BM_DIR/history.sh"
source "$BM_DIR/patch-manager.sh"
source "$BM_DIR/bundle-manager.sh"
source "$BM_DIR/manifest.sh"
source "$BM_DIR/verifier.sh"
source "$BM_DIR/update-state.sh"

# Generate a unique backup ID.
# Format: YYYYMMDD-HHMM-RANDOM
_generate_backup_id() {
    echo "$(date +%Y%m%d-%H%M)-$(head -c 2 /dev/urandom | xxd -p 2>/dev/null || echo '00')"
}

# Create a new, fully verified backup.
# Returns: echoes the new backup_id. 1 on failure.
backup_create() {
    config_load 2>/dev/null || true
    if ! locate_hermes_repo; then
        return "$EXIT_REPO_NOT_FOUND"
    fi
    cd_hermes_repo || return "$EXIT_REPO_NOT_FOUND"

    if [[ -z "${CONFIG_REMOTES_UPSTREAM:-}" || -z "${CONFIG_REMOTES_FORK:-}" ]]; then
        log_info "Remotes not configured, auto-detecting..."
        if ! auto_detect_remotes; then
            log_error "Could not auto-detect remotes. Please configure manually."
            return "$EXIT_VALIDATION_FAILURE"
        fi
        config_save
    fi

    if ! git_working_tree_clean; then
        log_info "Uncommitted changes detected, stashing..."
        git_stash_changes "pre-backup-$(date +%Y%m%d-%H%M)"
    fi

    local upstream_ref="${CONFIG_REMOTES_UPSTREAM:-origin}/main"
    local base_ref
    base_ref=$(git_merge_base "$upstream_ref" HEAD) || true
    if [[ -z "$base_ref" ]]; then
        log_warn "No merge-base with upstream ($upstream_ref), falling back to fork"
        local fork_ref="${CONFIG_REMOTES_FORK:-fork}/main"
        base_ref=$(git_merge_base "$fork_ref" HEAD) || true
        if [[ -z "$base_ref" ]]; then
            log_error "Could not find merge-base with upstream or fork"
            git_stash_pop 2>/dev/null || true
            return "$EXIT_GENERAL_ERROR"
        fi
        log_info "Using fork as base: $base_ref"
    fi

    local backup_id
    backup_id=$(_generate_backup_id)
    local backup_dir
    backup_dir=$(config_backup_dir)/"$backup_id"

    log_info "Creating backup: $backup_id"
    mkdir -p "$backup_dir/patches"

    local patch_count
    if ! patch_count=$(patch_export "$base_ref" "$backup_dir/patches"); then
        log_error "Failed to export patches"
        rm -rf "$backup_dir"
        git_stash_pop 2>/dev/null || true
        return "$EXIT_GENERAL_ERROR"
    fi

    local bundle_size
    if ! bundle_size=$(bundle_create "$backup_dir/backup.bundle"); then
        log_error "Failed to create bundle"
        rm -rf "$backup_dir"
        git_stash_pop 2>/dev/null || true
        return "$EXIT_GENERAL_ERROR"
    fi

    manifest_create "$backup_dir" "$backup_id" "$base_ref" "$patch_count" "$bundle_size"

    local tag_name="backup/$backup_id"
    git_create_tag "$tag_name" "Hermes backup: $backup_id"

    local tag_pushed="false"
    if git_push_tag "${CONFIG_REMOTES_FORK:-fork}" "$tag_name" 2>/dev/null; then
        tag_pushed="true"
        manifest_update_tag_pushed "$backup_dir" "true"
        log_info "Tag pushed to fork: $tag_name"
    else
        log_warn "Failed to push tag to fork (backup still available locally)"
    fi

    log_info "Verifying backup..."
    if verify_backup "$backup_dir" "$base_ref"; then
        log_success "Backup created and verified: $backup_id"
        history_log "backup_created" "success" "$patch_count patches, ${bundle_size} bytes, tag_pushed=$tag_pushed" "$backup_id"
    else
        log_error "Backup verification failed"
        history_log "backup_created" "failed" "verification failed" "$backup_id"
        git_stash_pop 2>/dev/null || true
        return "$EXIT_VERIFICATION_FAILURE"
    fi

    if git_stash_pop 2>/dev/null; then
        log_info "Restored stashed changes"
    fi

    echo ""
    echo "Backup: $backup_id"
    echo "  Patches: $patch_count files"
    echo "  Bundle: $(($bundle_size / 1024 / 1024))MB"
    echo "  Tag: $tag_name (pushed: $tag_pushed)"
    echo "  Location: $backup_dir"

    echo "$backup_id"
    return "$EXIT_SUCCESS"
}

# Compute a fingerprint of the current custom state for reuse detection.
backup_compute_fingerprint() {
    local upstream_ref="${CONFIG_REMOTES_UPSTREAM:-origin}/main"
    local base=""
    base=$(git_merge_base "$upstream_ref" HEAD 2>/dev/null) || true
    if [[ -z "$base" ]]; then
        base=$(git_merge_base "${CONFIG_REMOTES_FORK:-fork}/main" HEAD 2>/dev/null) || true
    fi
    local head=""
    head=$(git_current_commit 2>/dev/null) || true
    local shas=""
    if [[ -n "$base" ]]; then
        shas=$(git_commits_between "$base" HEAD 2>/dev/null | tr '\n' ',' ) || true
    fi
    local ver=""
    ver=$(hermes version 2>/dev/null | head -1) || true
    [[ -z "$ver" ]] && ver="unknown"
    echo "${head}|${shas}|${ver}"
}

# Find the newest verified backup by ID (IDs are YYYYMMDD-HHMM-xxxx, lexicographically chronological).
backup_latest_verified() {
    local backup_dir
    backup_dir=$(config_backup_dir 2>/dev/null)
    [[ -d "$backup_dir" ]] || return 0
    local latest="" latest_path=""
    local dir m
    for dir in "$backup_dir"/*/; do
        [[ -d "$dir" ]] || continue
        m="${dir}manifest.json"
        [[ -f "$m" ]] || continue
        grep -q '"status": "verified"' "$m" 2>/dev/null || continue
        if [[ -z "$latest" || "$(basename "$dir")" > "$latest" ]]; then
            latest=$(basename "$dir")
            latest_path="${dir%/}"
        fi
    done
    [[ -n "$latest" ]] && echo "${latest}|${latest_path}"
    return 0
}

# Check whether the current custom state matches a backup's recorded state.
backup_state_matches() {
    local bdir="$1"
    local m="$bdir/manifest.json"
    [[ -f "$m" ]] || return 1
    local rec
    rec=$(grep '"state_fingerprint"' "$m" 2>/dev/null | sed 's/.*: *"\([^"]*\)".*/\1/')
    [[ -n "$rec" ]] || return 1
    local cur
    cur=$(backup_compute_fingerprint) || true
    [[ "$rec" == "$cur" ]]
}

# Reuse the latest verified backup if the current state matches, otherwise create a new one.
backup_reuse_or_create() {
    local latest
    latest=$(backup_latest_verified 2>/dev/null) || true
    if [[ -n "$latest" ]]; then
        local bid path
        bid="${latest%%|*}"
        path="${latest##*|}"
        if backup_state_matches "$path"; then
            log_info "Current custom state matches latest verified backup ($bid) — reusing instead of creating a new backup"
            echo "${bid}|true"
            return 0
        fi
    fi
    log_info "No matching verified backup found — creating a new one"
    local new_id
    if ! new_id=$(backup_create 2>&1); then
        log_error "Backup creation failed"
        return 1
    fi
    echo "${new_id}|false"
    return 0
}

# Permanently remove a backup (directory + associated git tag).
backup_delete() {
    local id="$1" path="$2"
    if locate_hermes_repo 2>/dev/null; then
        cd_hermes_repo 2>/dev/null || true
        git tag -d "backup/$id" 2>/dev/null || true
        git push "${CONFIG_REMOTES_FORK:-fork}" ":refs/tags/backup/$id" 2>/dev/null || true
    fi
    rm -rf "$path"
    log_info "Removed old backup: $id"
}

# Apply the retention policy.
# After a successful update, remove old *verified* backups that exceed max_backups,
# while always protecting:
#   - the newest verified backup
#   - backups referenced by an interrupted (in-progress) update
#   - any unverified or failed backups
# Usage: backup_cleanup [--dry-run]
# Returns: 0 always (cleanup must never abort the update workflow).
backup_cleanup() {
    local dry_run=false
    [[ "${1:-}" == "--dry-run" ]] && dry_run=true

    config_load 2>/dev/null || true
    local auto_cleanup="${CONFIG_AUTO_CLEANUP:-true}"
    local max_backups="${CONFIG_MAX_BACKUPS:-0}"

    if [[ "$auto_cleanup" != "true" ]]; then
        log_info "Auto cleanup disabled (auto_cleanup=false) — retention skipped"
        return 0
    fi
    if [[ "${max_backups:-0}" -eq 0 ]]; then
        log_info "max_backups=0 (unlimited) — no retention pruning"
        return 0
    fi

    local backup_dir
    backup_dir=$(config_backup_dir)
    [[ -d "$backup_dir" ]] || return 0

    # Gather candidates and identify protected set.
    # IDs are YYYYMMDD-HHMM-xxxx -> lexicographic sort == chronological sort.
    local verified_ids=()
    local newest_verified="" interrupted_id=""
    local dir m id v

    # Newest verified (by ID).
    for dir in "$backup_dir"/*/; do
        [[ -d "$dir" ]] || continue
        m="${dir}manifest.json"
        [[ -f "$m" ]] || continue
        id=$(basename "$dir")
        v="unknown"
        grep -q '"status": "verified"' "$m" 2>/dev/null && v="verified"
        grep -q '"status": "failed"' "$m" 2>/dev/null && v="failed"
        if [[ "$v" == "verified" && ( -z "$newest_verified" || "$id" > "$newest_verified" ) ]]; then
            newest_verified="$id"
        fi
        # Collect all verified into array for sorting.
        if [[ "$v" == "verified" ]]; then
            verified_ids+=("$id")
        fi
    done

    # Interrupted-update referenced backup.
    if update_state_load 2>/dev/null && ! update_state_all_done; then
        interrupted_id=$(update_state_get backup_id)
    fi

    # Sort verified_ids ascending (oldest first).
    local n=${#verified_ids[@]} a b tmp
    for ((a = 0; a < n; a++)); do
        for ((b = a + 1; b < n; b++)); do
            if [[ "${verified_ids[$b]}" < "${verified_ids[$a]}" ]]; then
                tmp=${verified_ids[$a]}; verified_ids[$a]=${verified_ids[$b]}; verified_ids[$b]=$tmp
            fi
        done
    done

    local excess=${#verified_ids[@]}
    if (( excess <= max_backups )); then
        log_info "Retention OK: $excess verified backup(s), limit $max_backups — nothing to remove"
        return 0
    fi

    local remove_count=$(( excess - max_backups ))
    log_info "Retention: removing $remove_count old verified backup(s) (keeping $max_backups; protecting newest verified, interrupted-update, and unverified/failed)"
    local removed=0
    for id in "${verified_ids[@]}"; do
        if (( removed >= remove_count )); then break; fi
        # Protect newest verified + interrupted-update backup.
        if [[ "$id" == "$newest_verified" ]]; then continue; fi
        if [[ -n "$interrupted_id" && "$id" == "$interrupted_id" ]]; then continue; fi
        if $dry_run; then
            log_info "[dry-run] Would remove: $id"
        else
            backup_delete "$id" "$backup_dir/$id"
        fi
        removed=$((removed + 1))
    done
    return 0
}
