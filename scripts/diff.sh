#!/usr/bin/env bash
# Diff command for the custom-update skill.
# Compares current installation against upstream.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

source "$LIB_DIR/exit-codes.sh"
source "$LIB_DIR/logging.sh"
source "$LIB_DIR/git-utils.sh"
source "$LIB_DIR/repo-locator.sh"
source "$LIB_DIR/config.sh"

# Main diff function.
diff_main() {
    local verbose="${1:-}"

    # Load config
    config_load 2>/dev/null || true

    # Locate Hermes repo
    if ! locate_hermes_repo; then
        return "$EXIT_REPO_NOT_FOUND"
    fi
    cd_hermes_repo || return "$EXIT_REPO_NOT_FOUND"

    # Find merge-base
    local upstream_ref="${CONFIG_REMOTES_UPSTREAM:-origin}/main"
    local base_ref
    base_ref=$(git_merge_base "$upstream_ref" HEAD 2>/dev/null || echo "")

    if [[ -z "$base_ref" ]]; then
        log_warn "No merge-base with upstream ($upstream_ref), falling back to fork"
        local fork_ref="${CONFIG_REMOTES_FORK:-fork}/main"
        base_ref=$(git_merge_base "$fork_ref" HEAD 2>/dev/null || echo "")
        if [[ -z "$base_ref" ]]; then
            log_error "Could not find merge-base with upstream or fork"
            return "$EXIT_GENERAL_ERROR"
        fi
    fi

    # Get commit count
    local patch_count
    patch_count=$(git_commit_count "$base_ref" HEAD 2>/dev/null || echo "0")

    # Get modified files
    local modified_files
    modified_files=$(git diff --name-status "$base_ref" HEAD 2>/dev/null || echo "")

    # Count file changes
    local added modified deleted
    added=$(echo "$modified_files" | grep -c '^A' 2>/dev/null || true)
    modified=$(echo "$modified_files" | grep -c '^M' 2>/dev/null || true)
    deleted=$(echo "$modified_files" | grep -c '^D' 2>/dev/null || true)

    # Print summary
    echo "Custom changes vs upstream ($upstream_ref)"
    echo ""
    printf '  Custom commits: %s\n' "$patch_count"
    printf '  Modified files: %s\n' "$((added + modified + deleted))"
    printf '    Added: %s\n' "$added"
    printf '    Modified: %s\n' "$modified"
    printf '    Deleted: %s\n' "$deleted"
    echo ""

    # Print commit list
    echo "Commits:"
    git log --oneline "$base_ref..HEAD" 2>/dev/null | while read -r line; do
        printf '  %s\n' "$line"
    done
    echo ""

    # Print file changes
    echo "Files changed:"
    if [[ -n "$modified_files" ]]; then
        echo "$modified_files" | while IFS=$'\t' read -r status file; do
            case "$status" in
                A) printf '  + %s (added)\n' "$file" ;;
                M) printf '  ~ %s (modified)\n' "$file" ;;
                D) printf '  - %s (deleted)\n' "$file" ;;
                *) printf '  ? %s (%s)\n' "$file" "$status" ;;
            esac
        done
    else
        echo "  (no file changes)"
    fi

    # Verbose: show full diff
    if [[ "$verbose" == "--verbose" || "$verbose" == "-v" ]]; then
        echo ""
        echo "Full diff:"
        git diff "$base_ref" HEAD 2>/dev/null
    fi

    return "$EXIT_SUCCESS"
}

# Run the diff command
diff_main "$@"
