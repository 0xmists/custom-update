#!/usr/bin/env bash
# Git utility functions for the custom-update skill.
# Shared across all commands to avoid duplicated logic.

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/logging.sh"

# Check if Git is installed.
# Returns: 0 if installed, 1 if not.
git_check_installed() {
    if command -v git &>/dev/null; then
        return 0
    else
        log_error "Git is not installed"
        return 1
    fi
}

# Check if we're inside a Git repository.
# Returns: 0 if in a repo, 1 if not.
git_is_repo() {
    git rev-parse --git-dir &>/dev/null
}

# Get the Git repository root directory.
# Returns: 0 and echoes the path, or 1 if not in a repo.
git_repo_root() {
    if git_is_repo; then
        git rev-parse --show-toplevel 2>/dev/null
        return 0
    fi
    return 1
}

# Get the current branch name.
# Returns: 0 and echoes the branch name, or 1 if in detached HEAD.
git_current_branch() {
    local branch
    branch=$(git symbolic-ref --short HEAD 2>/dev/null) || return 1
    echo "$branch"
    return 0
}

# Get the current commit hash (short).
# Returns: 0 and echoes the short hash.
git_current_commit_short() {
    git rev-parse --short HEAD 2>/dev/null
}

# Get the current commit hash (full).
# Returns: 0 and echoes the full hash.
git_current_commit() {
    git rev-parse HEAD 2>/dev/null
}

# Find the merge-base between two refs.
# Usage: git_merge_base <ref1> <ref2>
# Returns: 0 and echoes the merge-base hash, or 1 on failure.
git_merge_base() {
    local ref1="$1"
    local ref2="$2"
    git merge-base "$ref1" "$ref2" 2>/dev/null
}

# Get commits between two refs (exclusive of base).
# Usage: git_commits_between <base> <head>
# Returns: 0 and echoes commit hashes (one per line).
git_commits_between() {
    local base="$1"
    local head="${2:-HEAD}"
    git log --format='%H' "${base}..${head}" 2>/dev/null
}

# Get the number of commits between two refs.
# Usage: git_commit_count <base> <head>
# Returns: 0 and echoes the count.
git_commit_count() {
    local base="$1"
    local head="${2:-HEAD}"
    git rev-list --count "${base}..${head}" 2>/dev/null
}

# Check if a ref exists.
# Usage: git_ref_exists <ref>
# Returns: 0 if exists, 1 if not.
git_ref_exists() {
    local ref="$1"
    git show-ref --verify --quiet "$ref" 2>/dev/null
}

# Check if the working tree is clean.
# Returns: 0 if clean, 1 if dirty.
git_working_tree_clean() {
    if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
        return 1
    fi
    return 0
}

# Stash uncommitted changes.
# Usage: git_stash_changes <message>
# Returns: 0 if stashed or no changes, 1 on failure.
git_stash_changes() {
    local message="$1"

    if ! git_working_tree_clean; then
        log_info "Stashing uncommitted changes..."
        git stash push -m "$message" 2>/dev/null
        return $?
    fi

    log_debug "No uncommitted changes to stash"
    return 0
}

# Pop stashed changes.
# Returns: 0 if popped or no stash, 1 on failure.
git_stash_pop() {
    if git stash list | grep -q 'stash@'; then
        log_info "Restoring stashed changes..."
        if git stash pop 2>/dev/null; then
            return 0
        else
            log_warn "git stash pop failed, trying git stash apply"
            git stash apply 2>/dev/null
            return $?
        fi
    fi
    log_debug "No stashed changes to restore"
    return 0
}

# Get list of remotes with their URLs.
# Returns: 0 and echoes "name URL" pairs (one per line).
git_list_remotes() {
    git remote -v 2>/dev/null | grep '(fetch)' | awk '{print $1, $2}'
}

# Get the URL for a specific remote.
# Usage: git_remote_url <remote_name>
# Returns: 0 and echoes the URL, or 1 if remote doesn't exist.
git_remote_url() {
    local remote="$1"
    git remote get-url "$remote" 2>/dev/null
}

# Push a tag to a remote.
# Usage: git_push_tag <remote> <tag>
# Returns: 0 on success, 1 on failure.
git_push_tag() {
    local remote="$1"
    local tag="$2"
    git push "$remote" "$tag" 2>/dev/null
}

# Create an annotated tag.
# Usage: git_create_tag <tag_name> <message>
# Returns: 0 on success, 1 on failure.
git_create_tag() {
    local tag="$1"
    local message="$2"
    git tag -a "$tag" -m "$message" 2>/dev/null
}
