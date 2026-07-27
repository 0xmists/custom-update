#!/usr/bin/env bash
# Status command for the custom-update skill.
# Shows the current state of the Hermes installation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

source "$LIB_DIR/exit-codes.sh"
source "$LIB_DIR/logging.sh"
source "$LIB_DIR/git-utils.sh"
source "$LIB_DIR/repo-locator.sh"
source "$LIB_DIR/config.sh"
source "$LIB_DIR/history.sh"
source "$LIB_DIR/update-state.sh"

# Main status function.
status_main() {
    # Load config
    config_load 2>/dev/null || true

    # Locate Hermes repo
    local repo_root
    if ! repo_root=$(locate_hermes_repo 2>/dev/null); then
        log_error "Hermes repository not found"
        return "$EXIT_REPO_NOT_FOUND"
    fi

    cd_hermes_repo || return "$EXIT_REPO_NOT_FOUND"

    echo "Hermes Custom Status"
    echo ""

    # Version
    local hermes_version
    hermes_version=$(hermes version 2>/dev/null | head -1 || echo "unknown")
    printf '  Version:        %s\n' "$hermes_version"

    # Upstream and current commits
    local upstream_ref="${CONFIG_REMOTES_UPSTREAM:-origin}/main"
    local upstream_commit current_commit
    upstream_commit=$(git rev-parse "$upstream_ref" 2>/dev/null | cut -c1-10 || echo "unknown")
    current_commit=$(git_current_commit_short 2>/dev/null || echo "unknown")

    local upstream_url fork_url
    upstream_url=$(git_remote_url "${CONFIG_REMOTES_UPSTREAM:-origin}" 2>/dev/null || echo "not configured")
    fork_url=$(git_remote_url "${CONFIG_REMOTES_FORK:-fork}" 2>/dev/null || echo "not configured")

    printf '  Upstream:       %s (%s)\n' "$upstream_commit" "$upstream_url"
    printf '  Current:        %s (%s)\n' "$current_commit" "$fork_url"

    # Custom patches
    local base_ref patch_count
    base_ref=$(git_merge_base "$upstream_ref" HEAD 2>/dev/null || echo "")
    if [[ -z "$base_ref" ]]; then
        # Fall back to fork if no merge-base with upstream
        local fork_ref="${CONFIG_REMOTES_FORK:-fork}/main"
        base_ref=$(git_merge_base "$fork_ref" HEAD 2>/dev/null || echo "")
    fi
    if [[ -n "$base_ref" ]]; then
        patch_count=$(git_commit_count "$base_ref" HEAD 2>/dev/null || echo "0")
        if [[ "$patch_count" -gt 0 ]]; then
            local patch_shas
            patch_shas=$(git_commits_between "$base_ref" HEAD 2>/dev/null | head -6 | cut -c1-10 | tr '\n' ',' | sed 's/,$//')
            printf '  Custom patches: %s applied (%s)\n' "$patch_count" "$patch_shas"
        else
            printf '  Custom patches: 0 (clean, no custom commits)\n'
        fi
    else
        printf '  Custom patches: unknown (cannot find merge-base)\n'
    fi

    # Latest backup
    local backup_dir latest_backup_id latest_backup_tag
    backup_dir=$(config_backup_dir)
    if [[ -d "$backup_dir" ]]; then
        latest_backup_id=$(find "$backup_dir" -maxdepth 1 -mindepth 1 -type d | sort -r | head -1 | xargs basename 2>/dev/null || echo "")
        if [[ -n "$latest_backup_id" ]]; then
            latest_backup_tag="backup/$latest_backup_id"
            printf '  Latest backup:  %s (%s)\n' "$latest_backup_id" "$latest_backup_tag"

            # Check if tag is pushed
            if git_ref_exists "refs/tags/$latest_backup_tag" 2>/dev/null; then
                local fork_has_tag="false"
                if git ls-remote "${CONFIG_REMOTES_FORK:-fork}" "refs/tags/$latest_backup_tag" 2>/dev/null | grep -q "$latest_backup_tag"; then
                    fork_has_tag="true"
                fi
                printf '  GitHub:         %s %s\n' "$latest_backup_tag" "$([[ "$fork_has_tag" == "true" ]] && echo '✓ pushed' || echo '✗ not pushed')"
            fi
        else
            printf '  Latest backup:  none\n'
        fi

        # Count total backups
        local total_backups
        total_backups=$(find "$backup_dir" -maxdepth 1 -mindepth 1 -type d | wc -l)
        printf '  Backups total:  %s\n' "$total_backups"
    else
        printf '  Latest backup:  none\n'
        printf '  Backups total:  0\n'
    fi

    # Working tree status
    local working_tree_status
    if git_working_tree_clean; then
        working_tree_status="Clean"
    else
        working_tree_status="Dirty"
        local dirty_files
        dirty_files=$(git status --porcelain 2>/dev/null | wc -l)
        working_tree_status="$working_tree_status ($dirty_files files)"
    fi
    printf '  Working tree:   %s\n' "$working_tree_status"

    # Stash status
    local stash_count
    stash_count=$(git stash list 2>/dev/null | wc -l)
    printf '  Stashed:        %s\n' "$([[ "$stash_count" -gt 0 ]] && echo "$stash_count entries" || echo 'None')"

    # Update provider
    printf '  Update provider: %s\n' "${CONFIG_UPDATE_PROVIDER:-hermes-update}"

    # Update state (resume support)
    if update_state_exists 2>/dev/null; then
        if update_state_load 2>/dev/null; then
            local _next_phase
            _next_phase=$(update_state_next_phase 2>/dev/null)
            if [[ -n "$_next_phase" ]]; then
                printf '  Update state:   in-progress (resume from: %s)\n' "$_next_phase"
                printf '  Backup reused:  %s\n' "$(update_state_get backup_reused 2>/dev/null || echo unknown)"
            else
                printf '  Update state:   complete (ready to clear)\n'
            fi
        fi
    else
        printf '  Update state:   none (no interrupted update)\n'
    fi

    # Backup reuse status
    local _reuse_status="no"
    if [[ -f "$backup_dir/.update-state" ]]; then
        _reuse_status=$(grep '^STATE_BACKUP_REUSED=' "$backup_dir/.update-state" 2>/dev/null | cut -d= -f2)
        [[ "$_reuse_status" == "true" ]] && _reuse_status="yes (last update reused a backup)"
        [[ -z "$_reuse_status" ]] && _reuse_status="no"
    fi
    printf '  Backup reuse:   %s\n' "$_reuse_status"

    # Cleanup policy
    printf '  Cleanup policy: max_backups=%s, auto_cleanup=%s\n' \
        "${CONFIG_MAX_BACKUPS:-0}" "${CONFIG_AUTO_CLEANUP:-true}"

    # Remotes
    printf '  Remotes:        upstream=%s, fork=%s\n' \
        "${CONFIG_REMOTES_UPSTREAM:-origin}" "${CONFIG_REMOTES_FORK:-fork}"

    return "$EXIT_SUCCESS"
}

# Run the status command
status_main "$@"
