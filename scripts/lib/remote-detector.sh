#!/usr/bin/env bash
# Remote detector for the custom-update skill.
# Automatically identifies upstream and fork remotes.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/logging.sh"
source "$SCRIPT_DIR/git-utils.sh"

# Known upstream repository URL patterns (match both SSH and HTTPS)
UPSTREAM_PATTERNS=(
    "NousResearch/hermes-agent"
    "NousResearch/hermes"
)

# Detect all remotes and classify them.
# Sets DETECTED_UPSTREAM and DETECTED_FORK variables.
# Returns: 0 on success, 1 if no remotes found.
detect_remotes() {
    local remotes
    remotes=$(git_list_remotes)

    if [[ -z "$remotes" ]]; then
        log_error "No Git remotes found"
        return 1
    fi

    DETECTED_UPSTREAM=""
    DETECTED_FORK=""
    local upstream_candidates=()
    local fork_candidates=()

    while IFS=' ' read -r name url; do
        [[ -z "$name" || -z "$url" ]] && continue

        # Check if this is the upstream (NousResearch)
        local is_upstream=false
        for pattern in "${UPSTREAM_PATTERNS[@]}"; do
            if [[ "$url" == *"$pattern"* ]]; then
                is_upstream=true
                break
            fi
        done

        if [[ "$is_upstream" == true ]]; then
            upstream_candidates+=("$name")
        else
            fork_candidates+=("$name")
        fi
    done <<< "$remotes"

    # Select the first upstream candidate
    if [[ ${#upstream_candidates[@]} -gt 0 ]]; then
        DETECTED_UPSTREAM="${upstream_candidates[0]}"
    fi

    # Select the first fork candidate
    if [[ ${#fork_candidates[@]} -gt 0 ]]; then
        DETECTED_FORK="${fork_candidates[0]}"
    fi

    # If no upstream found, check if there's only one remote (it might be the fork)
    if [[ -z "$DETECTED_UPSTREAM" && $(echo "$remotes" | wc -l) -eq 1 ]]; then
        DETECTED_FORK="${fork_candidates[0]}"
    fi

    return 0
}

# Display detected remotes and ask for confirmation.
# Returns: 0 if confirmed, 1 if declined.
confirm_remotes() {
    echo "Detected remotes:"
    echo ""

    local remotes
    remotes=$(git_list_remotes)

    while IFS=' ' read -r name url; do
        [[ -z "$name" || -z "$url" ]] && continue
        local role="fork"
        if [[ -n "$DETECTED_UPSTREAM" && "$name" == "$DETECTED_UPSTREAM" ]]; then
            role="upstream"
        fi
        printf '  %s → %s (%s)\n' "$name" "$url" "$role"
    done <<< "$remotes"

    echo ""
    echo "Configuration:"
    echo "  Upstream remote: ${DETECTED_UPSTREAM:-<not found>}"
    echo "  Fork remote:     ${DETECTED_FORK:-<not found>}"
    echo ""

    if [[ -z "$DETECTED_UPSTREAM" ]]; then
        echo "Warning: Could not automatically detect the upstream remote."
        echo "Please specify it manually with: hermes custom config set remotes.upstream <name>"
        echo ""
    fi

    printf 'Use these? [Y/n] '
    local response
    read -r response
    [[ "${response,,}" == "y" || "${response,,}" == "yes" || -z "$response" ]]
}

# Auto-detect remotes and save to config.
# Returns: 0 on success, 1 on failure.
auto_detect_remotes() {
    if ! detect_remotes; then
        return 1
    fi

    if ! confirm_remotes; then
        log_info "Remote detection cancelled"
        return 1
    fi

    CONFIG_REMOTES_UPSTREAM="$DETECTED_UPSTREAM"
    CONFIG_REMOTES_FORK="$DETECTED_FORK"

    log_success "Remotes configured: upstream=$CONFIG_REMOTES_UPSTREAM, fork=$CONFIG_REMOTES_FORK"
    return 0
}
