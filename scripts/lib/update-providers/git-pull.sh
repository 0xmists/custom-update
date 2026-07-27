#!/usr/bin/env bash
# Update provider: git-pull
# Uses git pull to update from upstream.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../logging.sh"

# Perform the update.
# Returns: 0 on success, 1 on failure.
provider_update() {
    local upstream="${CONFIG_REMOTES_UPSTREAM:-origin}"
    log_info "Updating Hermes via git pull $upstream main..."
    if git pull "$upstream" main 2>&1; then
        log_info "git pull completed"
        return 0
    else
        log_error "git pull failed"
        return 1
    fi
}

# Verify the update succeeded.
# Returns: 0 if update succeeded, 1 if failed.
provider_verify_update() {
    local prev_commit="$1"
    local current_commit
    current_commit=$(git rev-parse HEAD 2>/dev/null)

    if [[ -n "$current_commit" && "$current_commit" != "$prev_commit" ]]; then
        log_info "Update verified: $prev_commit -> $current_commit"
        return 0
    else
        log_error "Update verification failed: commit unchanged"
        return 1
    fi
}

# Get the current Hermes version.
# Returns: 0 and echoes the version string.
provider_get_version() {
    hermes version 2>/dev/null | head -1 || echo "unknown"
}
