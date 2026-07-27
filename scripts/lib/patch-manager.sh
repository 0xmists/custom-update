#!/usr/bin/env bash
# Patch manager for the custom-update skill.
# Handles exporting custom commits as patches.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/git-utils.sh"
source "$SCRIPT_DIR/logging.sh"

# Export patches as patches.
# Usage: patch_export <base_ref> <output_dir>
# Returns: 0 on success, 1 on failure.
# Echoes: number of patches exported.
patch_export() {
    local base_ref="$1"
    local output_dir="$2"

    mkdir -p "$output_dir"

    # Export patches with 3-way merge support (if available)
    local patch_output
    patch_output=$(git format-patch --3way "$base_ref..HEAD" -o "$output_dir" 2>&1)
    local result=$?

    if (( result != 0 )); then
        # Fallback: try without --3way (not supported on all git builds)
        log_warn "git format-patch --3way not supported, retrying without"
        patch_output=$(git format-patch "$base_ref..HEAD" -o "$output_dir" 2>&1)
        result=$?
    fi

    if (( result != 0 )); then
        log_error "Failed to export patches: $patch_output"
        return 1
    fi

    # Count patches
    local count
    count=$(find "$output_dir" -name '*.patch' | wc -l)
    log_info "Exported $count patches to $output_dir"
    echo "$count"
    return 0
}

# Verify patches can be checked.
# Usage: patch_verify <patch_dir> [base_ref]
# If base_ref is provided, creates a temporary worktree at base_ref and applies
# patches in sequence so dependencies between patches are handled correctly.
# Returns: 0 if all patches are valid, 1 if any fail.
patch_verify() {
    local patch_dir="$1"
    local base_ref="${2:-}"
    local failed=0
    local worktree_dir=""

    # If base ref is provided, create a temporary worktree for verification
    if [[ -n "$base_ref" ]]; then
        worktree_dir=$(mktemp -d 2>/dev/null || echo "")
        if [[ -n "$worktree_dir" ]] && git worktree add "$worktree_dir" "$base_ref" 2>/dev/null; then
            log_debug "Created temporary worktree at $worktree_dir for patch verification"

            # Apply patches in sequence so dependencies between patches are handled
            for patch in "$patch_dir"/*.patch; do
                [[ -f "$patch" ]] || continue
                if (cd "$worktree_dir" && git apply --check "$patch" 2>/dev/null); then
                    # Apply the patch to the worktree for subsequent patches
                    if ! (cd "$worktree_dir" && git apply "$patch" 2>/dev/null); then
                        log_error "Patch apply failed: $(basename "$patch")"
                        failed=1
                        break
                    fi
                else
                    log_error "Patch verification failed: $(basename "$patch")"
                    failed=1
                    break
                fi
            done
        else
            log_warn "Failed to create temporary worktree, falling back to current tree"
            rm -rf "$worktree_dir" 2>/dev/null || true
            worktree_dir=""

            for patch in "$patch_dir"/*.patch; do
                [[ -f "$patch" ]] || continue
                if ! git apply --check "$patch" 2>/dev/null; then
                    log_error "Patch verification failed: $(basename "$patch")"
                    failed=1
                fi
            done
        fi
    else
        for patch in "$patch_dir"/*.patch; do
            [[ -f "$patch" ]] || continue
            if ! git apply --check "$patch" 2>/dev/null; then
                log_error "Patch verification failed: $(basename "$patch")"
                failed=1
            fi
        done
    fi

    # Clean up temporary worktree
    if [[ -n "$worktree_dir" ]]; then
        git worktree remove "$worktree_dir" --force 2>/dev/null || true
        rm -rf "$worktree_dir" 2>/dev/null || true
    fi

    if (( failed == 0 )); then
        log_info "All patches verified"
    fi
    return $failed
}

# Get list of patch files.
# Usage: patch_list <patch_dir>
# Returns: 0 and echoes patch file paths (one per line).
patch_list() {
    local patch_dir="$1"
    find "$patch_dir" -name '*.patch' | sort
}
