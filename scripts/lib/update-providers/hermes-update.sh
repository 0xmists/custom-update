#!/usr/bin/env bash
# Update provider: hermes-update (adapter-shared).
# Delegates all update execution to hermes-adapter.sh.
# No update logic lives here — only the provider identity.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$(dirname "$SCRIPT_DIR")/.." && pwd)/scripts/lib"
source "$LIB_DIR/logging.sh"
source "$LIB_DIR/hermes-adapter.sh"
source "$LIB_DIR/config.sh"

# Perform the update via the Hermes adapter.
# Returns: 0 on success, non-zero on failure.
provider_update() {
    hermes_execute_update
}

# Verify the update succeeded.
# Uses the Hermes adapter's health check.
# Returns: 0 if update succeeded, 1 if failed.
provider_verify_update() {
    local prev_commit="${1:-}"
    local current_commit
    current_commit=$(git rev-parse HEAD 2>/dev/null)

    if [[ -n "$prev_commit" && "$current_commit" != "$prev_commit" ]]; then
        log_info "Update verified: $prev_commit -> $current_commit"
        return 0
    fi

    # Even if no commit change, verify Hermes is healthy.
    if hermes_verify_healthy 2>/dev/null; then
        log_info "Update verified: Hermes is healthy (no commit change — may already be current)"
        return 0
    fi

    log_error "Update verification failed"
    return 1
}

# Get the current Hermes version via the adapter.
# Returns: 0 and echoes the version string.
provider_get_version() {
    hermes_version
}