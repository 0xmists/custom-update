#!/usr/bin/env bash
# Update command for the custom-update skill.
# Phase-based workflow: Backup -> Update -> Apply -> Verify -> Publish.
# Each phase persists its status; interrupted runs resume from the last
# incomplete phase. Custom patches are NEVER applied until the upstream
# update and dependency installation have completed and verified successfully.
# Any phase failure aborts immediately with the exact error.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

source "$LIB_DIR/exit-codes.sh"
source "$LIB_DIR/logging.sh"
source "$LIB_DIR/git-utils.sh"
source "$LIB_DIR/repo-locator.sh"
source "$LIB_DIR/config.sh"
source "$LIB_DIR/history.sh"
source "$LIB_DIR/update-state.sh"
source "$LIB_DIR/backup-manager.sh"

# ---------------------------------------------------------------------------
# Phase helpers
# ---------------------------------------------------------------------------

# Run the configured update provider (hermes update or git pull).
# Returns: 0 on success, non-zero on failure. Echoes the provider's output.
_run_provider_update() {
    local provider="${CONFIG_UPDATE_PROVIDER:-hermes-update}"
    case "$provider" in
        hermes-update)
            hermes update 2>&1
            ;;
        git-pull)
            local upstream="${CONFIG_REMOTES_UPSTREAM:-origin}"
            git pull "$upstream" main 2>&1
            ;;
        *)
            log_error "Unknown update provider: $provider"
            return "$EXIT_GENERAL_ERROR"
            ;;
    esac
}

# Verify Hermes starts correctly after an update.
# Runs `hermes version` (which exercises the installed CLI + Python env).
# Returns: 0 if Hermes is functional, 1 otherwise.
_verify_hermes_starts() {
    local ver
    ver=$(hermes version 2>&1 | head -1) || true
    if [[ -z "$ver" || "$ver" == *"Traceback"* || "$ver" == *"Error"* ]]; then
        log_error "Hermes does not start after update (version output: $ver)"
        return 1
    fi
    log_info "Hermes starts OK after update: $ver"
    return 0
}

# Apply custom patches (no-op when there are none).
# Returns: 0 on success, non-zero on failure.
_run_apply() {
    local base_ref patch_count
    base_ref=$(git_merge_base "${CONFIG_REMOTES_UPSTREAM:-origin}/main" HEAD 2>/dev/null) || true
    if [[ -z "$base_ref" ]]; then
        base_ref=$(git_merge_base "${CONFIG_REMOTES_FORK:-fork}/main" HEAD 2>/dev/null) || true
    fi
    if [[ -n "$base_ref" ]]; then
        patch_count=$(git_commit_count "$base_ref" HEAD 2>/dev/null || echo 0)
    else
        patch_count=0
    fi

    if [[ "${patch_count:-0}" -eq 0 ]]; then
        log_info "No custom patches to apply (clean)"
        return 0
    fi

    log_info "Applying $patch_count custom patch(es)..."
    if patch_apply "$base_ref"; then
        log_success "Patches applied"
        return 0
    else
        log_error "Patch application failed (conflict or error)"
        return "$EXIT_PATCH_CONFLICT"
    fi
}

# Run health checks (doctor) for the current build.
# Returns: 0 if healthy, 1 otherwise.
_run_health_checks() {
    if bash "$SCRIPT_DIR/doctor.sh" 2>&1; then
        return 0
    else
        log_error "Health checks (doctor) failed"
        return 1
    fi
}

# Publish: push updated custom branch/commits to the configured remote.
# Returns: 0 on success, non-zero on failure.
_run_publish() {
    local fork="${CONFIG_REMOTES_FORK:-fork}"
    local branch
    branch=$(git_current_branch 2>/dev/null) || branch="main"

    log_info "Publishing updated build to $fork ($branch)..."
    if git push "$fork" "$branch" 2>&1; then
        log_success "Published $branch to $fork"
        return 0
    else
        log_error "Failed to push $branch to $fork"
        return "$EXIT_GENERAL_ERROR"
    fi
}

# ---------------------------------------------------------------------------
# Phase executors — each returns 0 on success, non-zero on failure.
# On failure the caller sets the phase to "pending" and marks interrupted.
# ---------------------------------------------------------------------------

_phase_backup() {
    log_info "=== Phase 1/5: Backup ==="
    update_state_set backup "in_progress"

    local reuse_out backup_id reused="false"
    if ! reuse_out=$(backup_reuse_or_create 2>&1); then
        log_error "Backup phase failed: could not create or reuse a backup"
        return "$EXIT_GENERAL_ERROR"
    fi
    backup_id="${reuse_out%%|*}"
    reused="${reuse_out##*|}"

    update_state_set backup_id "$backup_id"
    update_state_set backup_reused "$reused"
    update_state_set backup "done"

    if [[ "$reused" == "true" ]]; then
        log_success "Phase 1 complete: reused existing backup ($backup_id)"
    else
        log_success "Phase 1 complete: created new backup ($backup_id)"
    fi
    return 0
}

_phase_update() {
    log_info "=== Phase 2/5: Update (upstream + dependencies) ==="
    update_state_set update "in_progress"

    local prev_commit
    prev_commit=$(git_current_commit_short)

    log_info "Running upstream update (this may take several minutes for dependency installation / Rust-C compilation)..."
    local out rc=0
    out=$(_run_provider_update 2>&1) || rc=$?
    echo "$out"

    if [[ $rc -ne 0 ]]; then
        log_error "Update failed (exit $rc). Upstream update did NOT complete."
        return "$EXIT_GENERAL_ERROR"
    fi

    local new_commit
    new_commit=$(git_current_commit_short)
    if [[ "$prev_commit" == "$new_commit" ]]; then
        log_warn "No commit change detected after update (may already be current)"
    else
        log_success "Hermes updated: $prev_commit -> $new_commit"
    fi

    # Verify Hermes starts correctly before allowing any custom code.
    if ! _verify_hermes_starts; then
        log_error "Hermes does not start after update — aborting before applying custom patches"
        return "$EXIT_GENERAL_ERROR"
    fi

    update_state_set update "done"
    log_success "Phase 2 complete: upstream update + dependency installation verified"
    return 0
}

_phase_apply() {
    log_info "=== Phase 3/5: Apply (custom patches) ==="
    update_state_set apply "in_progress"

    # Safety gate: never apply patches unless Phase 2 succeeded.
    if [[ "$(update_state_get update)" != "done" ]]; then
        log_error "Cannot apply patches: Phase 2 (update) did not complete successfully"
        return "$EXIT_GENERAL_ERROR"
    fi

    if ! _run_apply; then
        log_error "Apply phase failed"
        return "$EXIT_PATCH_CONFLICT"
    fi

    update_state_set apply "done"
    log_success "Phase 3 complete: custom patches applied"
    return 0
}

_phase_verify() {
    log_info "=== Phase 4/5: Verify (custom build health) ==="
    update_state_set verify "in_progress"

    # Safety gate: never verify custom build unless patches applied (or clean).
    if [[ "$(update_state_get apply)" != "done" ]]; then
        log_error "Cannot verify custom build: Phase 3 (apply) did not complete successfully"
        return "$EXIT_GENERAL_ERROR"
    fi

    # Verify Hermes starts with custom changes applied.
    if ! _verify_hermes_starts; then
        log_error "Hermes does not start with custom changes applied"
        return "$EXIT_GENERAL_ERROR"
    fi

    # Run health checks.
    if ! _run_health_checks; then
        log_error "Health checks failed after custom build"
        return "$EXIT_GENERAL_ERROR"
    fi

    update_state_set verify "done"
    log_success "Phase 4 complete: custom build verified"
    return 0
}

_phase_publish() {
    log_info "=== Phase 5/5: Publish (push + cleanup) ==="
    update_state_set publish "in_progress"

    # Safety gate: never publish unless verification passed.
    if [[ "$(update_state_get verify)" != "done" ]]; then
        log_error "Cannot publish: Phase 4 (verify) did not complete successfully"
        return "$EXIT_GENERAL_ERROR"
    fi

    # Push updated custom branch/commits.
    if ! _run_publish; then
        log_error "Publish phase failed: could not push to remote"
        return "$EXIT_GENERAL_ERROR"
    fi

    # Update manifest/state files.
    log_info "Updating manifest and state files..."
    local backup_id
    backup_id=$(update_state_get backup_id)
    local bdir
    bdir=$(config_backup_dir)/"$backup_id"
    if [[ -d "$bdir" && -f "$bdir/manifest.json" ]]; then
        manifest_update_tag_pushed "$bdir" "true" 2>/dev/null || true
    fi

    # Perform backup cleanup according to retention policy.
    log_info "Running backup cleanup (retention policy)..."
    backup_cleanup || true

    update_state_set publish "done"
    log_success "Phase 5 complete: published and cleaned up"
    return 0
}

# ---------------------------------------------------------------------------
# Main workflow
# ---------------------------------------------------------------------------

update_main() {
    config_load 2>/dev/null || true

    if ! locate_hermes_repo; then
        return "$EXIT_REPO_NOT_FOUND"
    fi
    cd_hermes_repo || return "$EXIT_REPO_NOT_FOUND"

    # Load or initialize the update state.
    if ! update_state_load 2>/dev/null; then
        update_state_init
        update_state_load
    fi

    # Decide resume vs fresh.
    if ! update_state_all_done; then
        local resume_at
        resume_at=$(update_state_next_phase)
        log_info "Resuming interrupted update at phase: ${resume_at:-none}"
        log_info "State: backup=$(update_state_get backup) update=$(update_state_get update) apply=$(update_state_get apply) verify=$(update_state_get verify) publish=$(update_state_get publish)"
    else
        update_state_init
        update_state_load
        log_info "Starting new update workflow"
    fi

    # Execute phases in strict order. Abort immediately on any failure.
    local phase rc
    for phase in "${UPDATE_PHASES[@]}"; do
        # Skip already-completed phases (resume).
        if [[ "$(update_state_get "$phase")" == "done" ]]; then
            log_info "Phase '$phase' already complete — skipping"
            continue
        fi

        case "$phase" in
            backup)  _phase_backup  || rc=$? ;;
            update)  _phase_update  || rc=$? ;;
            apply)   _phase_apply   || rc=$? ;;
            verify)  _phase_verify  || rc=$? ;;
            publish) _phase_publish || rc=$? ;;
            *)       log_error "Unknown phase: $phase"; rc=$EXIT_GENERAL_ERROR ;;
        esac

        if [[ ${rc:-0} -ne 0 ]]; then
            # Mark the failed phase as pending and record interruption.
            update_state_set "$phase" "pending"
            update_state_set interrupted "true"
            history_log "update_completed" "failed" "phase=$phase, rc=$rc, provider=${CONFIG_UPDATE_PROVIDER:-hermes-update}" ""
            log_error "Workflow aborted at phase '$phase' (exit $rc). State saved for resume."
            log_error "Run 'hermes custom update' again to resume from this phase."
            return "$rc"
        fi
        rc=0
    done

    # All phases done — record success and clear state.
    history_log "update_completed" "success" "provider=${CONFIG_UPDATE_PROVIDER:-hermes-update}, backup_id=$(update_state_get backup_id), reused=$(update_state_get backup_reused)" ""
    update_state_clear

    echo ""
    echo "Hermes update workflow complete (all 5 phases)"
    echo "  Backup:    $(update_state_get backup_id 2>/dev/null || echo done)"
    echo "  Reused:    $(update_state_get backup_reused 2>/dev/null || echo unknown)"
    echo "  Published: yes"

    return "$EXIT_SUCCESS"
}

update_main "$@"
