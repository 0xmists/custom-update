#!/usr/bin/env bash
# Repository locator for the custom-update skill.
# Uses the Hermes adapter layer to find and validate the Hermes installation.
# No hardcoded paths remain — all resolution is delegated to hermes-adapter.sh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")"
source "$LIB_DIR/logging.sh"
source "$LIB_DIR/exit-codes.sh"
source "$LIB_DIR/hermes-adapter.sh"
source "$LIB_DIR/config.sh"
source "$LIB_DIR/git-utils.sh"

# Locate the Hermes repository root.
# Delegates to hermes_resolve_root in hermes-adapter.sh.
# Sets HERMES_REPO_ROOT on success.
# Returns: 0 if found, EXIT_REPO_NOT_FOUND (6) if not.
locate_hermes_repo() {
    local root
    if root=$(hermes_resolve_root); then
        HERMES_REPO_ROOT="$root"
        log_debug "Located Hermes repo via adapter: $HERMES_REPO_ROOT"
        return 0
    fi

    log_error "Hermes repository not found"
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

    if ! hermes_resolve_root 2>/dev/null; then
        log_error "Hermes repository is not accessible: $HERMES_REPO_ROOT"
        return "$EXIT_VALIDATION_FAILURE"
    fi

    # Verify it is a Git repository.
    if ! git_is_repo; then
        log_error "Not a Git repository: $HERMES_REPO_ROOT"
        return "$EXIT_VALIDATION_FAILURE"
    fi

    log_debug "Hermes repository validated: $HERMES_REPO_ROOT"
    return 0
}

# Change to the Hermes repository root.
# Returns: 0 on success, non-zero on failure.
cd_hermes_repo() {
    if [[ -z "${HERMES_REPO_ROOT:-}" ]]; then
        locate_hermes_repo || return "$EXIT_REPO_NOT_FOUND"
    fi

    cd "$HERMES_REPO_ROOT" || return 1
}