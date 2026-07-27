#!/usr/bin/env bash
# Doctor command for the custom-update skill.
# Verifies environment health before performing operations.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

source "$LIB_DIR/exit-codes.sh"
source "$LIB_DIR/logging.sh"
source "$LIB_DIR/git-utils.sh"
source "$LIB_DIR/repo-locator.sh"
source "$LIB_DIR/config.sh"
source "$LIB_DIR/remote-detector.sh"

# Check disk space.
# Returns: 0 and echoes available space in bytes, or 1 on failure.
_check_disk_space() {
    local path="$1"
    local available

    if [[ "$OSTYPE" == "darwin"* ]]; then
        available=$(df -k "$path" 2>/dev/null | tail -1 | awk '{print $4 * 1024}')
    else
        available=$(df -B1 "$path" 2>/dev/null | tail -1 | awk '{print $4}')
    fi

    if [[ -z "$available" || "$available" -eq 0 ]]; then
        return 1
    fi

    echo "$available"
    return 0
}

# Check if a command is available.
# Usage: _check_command <command>
# Returns: 0 if available, 1 if not.
_check_command() {
    local cmd="$1"
    command -v "$cmd" &>/dev/null
}

# Check if a Git remote is reachable.
# Usage: _check_remote_reachable <remote_name>
# Returns: 0 if reachable, 1 if not.
_check_remote_reachable() {
    local remote="$1"

    if ! git_ref_exists "refs/remotes/$remote/HEAD" 2>/dev/null; then
        # Try to fetch
        if git fetch --dry-run "$remote" HEAD 2>/dev/null; then
            return 0
        fi
        return 1
    fi

    return 0
}

# Check GitHub authentication.
# Returns: 0 if authenticated, 1 if not.
_check_github_auth() {
    # Check if gh CLI is available and authenticated
    if _check_command gh; then
        if gh auth status 2>/dev/null; then
            return 0
        fi
    fi

    # Check if git can push to the fork (SSH or HTTPS with credentials)
    # This is a best-effort check
    local fork_remote="${CONFIG_REMOTES_FORK:-fork}"
    if git push --dry-run "$fork_remote" HEAD 2>/dev/null; then
        return 0
    fi

    # Check for SSH agent
    if [[ -n "${SSH_AUTH_SOCK:-}" ]]; then
        return 0
    fi

    return 1
}

# Run the doctor command.
# Returns: 0 if all checks pass, EXIT_VALIDATION_FAILURE (2) if any fail.
doctor_main() {
    local errors=0
    local warnings=0

    echo "Hermes Custom Doctor"
    echo ""

    # 1. Check Git installed
    if git_check_installed; then
        local git_version
        git_version=$(git --version | awk '{print $3}')
        printf '  ✓ Git installed (v%s)\n' "$git_version"
    else
        printf '  ✗ Git not installed\n'
        errors=$((errors + 1))
    fi

    # 2. Locate Hermes repository
    if locate_hermes_repo; then
        printf '  ✓ Hermes repository found: %s\n' "$HERMES_REPO_ROOT"
    else
        printf '  ✗ Hermes repository not found\n'
        errors=$((errors + 1))
        echo ""
        echo "Errors: $errors"
        return "$EXIT_VALIDATION_FAILURE"
    fi

    # 3. Validate repository
    if validate_hermes_repo; then
        printf '  ✓ Repository is valid\n'
    else
        printf '  ✗ Repository validation failed\n'
        errors=$((errors + 1))
    fi

    # 4. Check current branch
    local current_branch
    if current_branch=$(git_current_branch); then
        printf '  ✓ Current branch: %s\n' "$current_branch"
    else
        printf '  ✗ Detached HEAD state\n'
        warnings=$((warnings + 1))
    fi

    # 5. Check remotes
    if [[ -n "${CONFIG_REMOTES_UPSTREAM:-}" ]]; then
        if _check_remote_reachable "$CONFIG_REMOTES_UPSTREAM"; then
            local upstream_url
            upstream_url=$(git_remote_url "$CONFIG_REMOTES_UPSTREAM")
            printf '  ✓ Upstream reachable (%s → %s)\n' "$CONFIG_REMOTES_UPSTREAM" "$upstream_url"
        else
            printf '  ✗ Upstream not reachable (%s)\n' "$CONFIG_REMOTES_UPSTREAM"
            errors=$((errors + 1))
        fi
    else
        printf '  ⚠ Upstream remote not configured\n'
        warnings=$((warnings + 1))
    fi

    if [[ -n "${CONFIG_REMOTES_FORK:-}" ]]; then
        if _check_remote_reachable "$CONFIG_REMOTES_FORK"; then
            local fork_url
            fork_url=$(git_remote_url "$CONFIG_REMOTES_FORK")
            printf '  ✓ Fork reachable (%s → %s)\n' "$CONFIG_REMOTES_FORK" "$fork_url"
        else
            printf '  ✗ Fork not reachable (%s)\n' "$CONFIG_REMOTES_FORK"
            errors=$((errors + 1))
        fi
    else
        printf '  ⚠ Fork remote not configured\n'
        warnings=$((warnings + 1))
    fi

    # 6. Check GitHub authentication
    if _check_github_auth; then
        printf '  ✓ GitHub authentication: ✓\n'
    else
        printf '  ⚠ GitHub authentication: not verified\n'
        warnings=$((warnings + 1))
    fi

    # 7. Check backup directory
    local backup_dir
    backup_dir=$(config_backup_dir)
    if [[ ! -d "$backup_dir" ]]; then
        mkdir -p "$backup_dir" 2>/dev/null
    fi
    if [[ -d "$backup_dir" && -w "$backup_dir" ]]; then
        printf '  ✓ Backup directory writable (%s)\n' "$backup_dir"
    else
        printf '  ✗ Backup directory not writable (%s)\n' "$backup_dir"
        errors=$((errors + 1))
    fi

    # 8. Check disk space
    local available_space
    if available_space=$(_check_disk_space "$backup_dir"); then
        local min_space=$((500 * 1024 * 1024))  # 500MB minimum
        if (( available_space >= min_space )); then
            local available_gb=$((available_space / 1024 / 1024 / 1024))
            printf '  ✓ Disk space: %sGB available (minimum: 500MB)\n' "$available_gb"
        else
            printf '  ⚠ Disk space: %sMB available (minimum: 500MB)\n' "$((available_space / 1024 / 1024))"
            warnings=$((warnings + 1))
        fi
    else
        printf '  ⚠ Cannot check disk space\n'
        warnings=$((warnings + 1))
    fi

    # 9. Check git bundle
    local bundle_output
    bundle_output=$(git bundle --help 2>&1 || true)
    if [[ "$bundle_output" == *"warning: failed to exec"* ]] || [[ "$bundle_output" == *"usage:"* ]]; then
        printf '  ✓ git bundle available\n'
    else
        printf '  ✗ git bundle not available\n'
        errors=$((errors + 1))
    fi

    # 10. Check git am
    local am_output
    am_output=$(git am --help 2>&1 || true)
    if [[ "$am_output" == *"warning: failed to exec"* ]] || [[ "$am_output" == *"usage:"* ]]; then
        printf '  ✓ git am available\n'
    else
        printf '  ✗ git am not available\n'
        errors=$((errors + 1))
    fi

    # 11. Check git rerere
    if git config --get rerere.enabled &>/dev/null; then
        printf '  ✓ git rerere: enabled\n'
    else
        printf '  ⚠ git rerere: disabled\n'
        warnings=$((warnings + 1))
    fi

    echo ""

    if (( errors > 0 )); then
        printf 'Errors: %d, Warnings: %d\n' "$errors" "$warnings"
        return "$EXIT_VALIDATION_FAILURE"
    elif (( warnings > 0 )); then
        printf 'All checks passed with %d warnings.\n' "$warnings"
        return 0
    else
        printf 'All checks passed.\n'
        return 0
    fi
}

# Run the doctor command
doctor_main "$@"
