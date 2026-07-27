#!/usr/bin/env bash
# Repository locator for the custom-update skill.
# Automatically finds and validates the Hermes repository.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/logging.sh"
source "$SCRIPT_DIR/exit-codes.sh"

# Common locations where Hermes might be installed.
HERMES_REPO_CANDIDATES=(
    "$HOME/.hermes/hermes-agent"
    "$HOME/hermes-agent"
    "$HOME/.hermes/hermes-agent/venv"
    "/data/data/com.termux/files/home/.hermes/hermes-agent"
)

# Check if a directory is a valid Hermes repository.
# Usage: _is_hermes_repo <path>
# Returns: 0 if valid, 1 if not.
_is_hermes_repo() {
    local dir="$1"

    [[ -d "$dir/.git" ]] || return 1
    [[ -f "$dir/run_agent.py" ]] || return 1
    [[ -f "$dir/hermes" ]] || return 1
    [[ -d "$dir/agent" ]] || return 1

    return 0
}

# Walk up from current directory to find a Git repository.
# Returns: 0 and echoes the path, or 1 if not found.
_find_repo_upward() {
    local dir="$PWD"

    while [[ "$dir" != "/" ]]; do
        if _is_hermes_repo "$dir"; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done

    return 1
}

# Check common locations for the Hermes repository.
# Returns: 0 and echoes the path, or 1 if not found.
_find_repo_common_locations() {
    local candidate

    for candidate in "${HERMES_REPO_CANDIDATES[@]}"; do
        if _is_hermes_repo "$candidate"; then
            echo "$candidate"
            return 0
        fi
    done

    return 1
}

# Locate the Hermes repository.
# Checks current directory tree first, then common locations.
# Sets HERMES_REPO_ROOT on success.
# Returns: 0 if found, EXIT_REPO_NOT_FOUND (6) if not.
locate_hermes_repo() {
    local repo_root

    # Try walking up from current directory
    if repo_root=$(_find_repo_upward); then
        HERMES_REPO_ROOT="$repo_root"
        log_debug "Found Hermes repo: $HERMES_REPO_ROOT"
        return 0
    fi

    # Try common locations
    if repo_root=$(_find_repo_common_locations); then
        HERMES_REPO_ROOT="$repo_root"
        log_debug "Found Hermes repo: $HERMES_REPO_ROOT"
        return 0
    fi

    log_error "Hermes repository not found"
    log_error "Searched: current directory tree, ${HERMES_REPO_CANDIDATES[*]}"
    log_error "Run this command from inside your Hermes repository, or set HERMES_REPO_ROOT manually."
    return "$EXIT_REPO_NOT_FOUND"
}

# Validate that the located repository is usable.
# Requires HERMES_REPO_ROOT to be set.
# Returns: 0 if valid, EXIT_VALIDATION_FAILURE (2) if not.
validate_hermes_repo() {
    if [[ -z "${HERMES_REPO_ROOT:-}" ]]; then
        log_error "HERMES_REPO_ROOT is not set"
        return "$EXIT_VALIDATION_FAILURE"
    fi

    if [[ ! -d "$HERMES_REPO_ROOT/.git" ]]; then
        log_error "Not a Git repository: $HERMES_REPO_ROOT"
        return "$EXIT_VALIDATION_FAILURE"
    fi

    if [[ ! -f "$HERMES_REPO_ROOT/run_agent.py" ]]; then
        log_error "Not a Hermes repository: $HERMES_REPO_ROOT"
        return "$EXIT_VALIDATION_FAILURE"
    fi

    return 0
}

# Change to the Hermes repository root.
# Returns: 0 on success, non-zero on failure.
cd_hermes_repo() {
    if [[ -z "${HERMES_REPO_ROOT:-}" ]]; then
        locate_hermes_repo || return $?
    fi

    cd "$HERMES_REPO_ROOT" || return 1
}
