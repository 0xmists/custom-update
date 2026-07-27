#!/usr/bin/env bash
# Hermes Adapter Layer
# ====================
# Isolates all Hermes-specific commands, paths, version detection,
# update execution, and health verification behind a clean interface.
#
# The goal: custom-update should never need to know WHERE Hermes is
# installed, HOW it is invoked, or WHAT its internal structure looks
# like. All of that lives here. Swap this adapter and the rest of the
# skill keep working unchanged.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/logging.sh"
source "$SCRIPT_DIR/exit-codes.sh"
source "$SCRIPT_DIR/config.sh"

# ---------------------------------------------------------------------------
# HermES INSTALLATION PATH RESOLUTION
# ---------------------------------------------------------------------------

# Search order (first match wins):
#   1. HERMES_ROOT env var
#   2. HERMES_HOME env var (derive from ~/.hermes/hermes-agent)
#   3. Common filesystem locations
#   4. Auto-detection via `which hermes`
#
# Sets HERMES_ROOT on success.

HERMES_ROOT="${HERMES_ROOT:-}"
HERMES_CONFIG_DIR="${HERMES_CONFIG_DIR:-$HOME/.hermes}"
HERMES_DATA_DIR="${HERMES_DATA_DIR:-$HOME/.hermes}"

# Known Hermes installation candidates.
_hermes_candidates=(
    "${HERMES_ROOT:-}"
    "$HOME/.hermes/hermes-agent"
    "$HOME/hermes-agent"
    "$HOME/.hermes"
    "/data/data/com.termux/files/home/.hermes/hermes-agent"
    "/data/data/com.termux/files/home/.hermes"
    "$(command -v hermes 2>/dev/null | xargs dirname 2>/dev/null)"
)

# Resolve HERMES_ROOT from the environment or filesystem.
# Returns 0 and sets HERMES_ROOT, or returns EXIT_REPO_NOT_FOUND (6).
hermes_resolve_root() {
    # If already set and valid, use it.
    if [[ -n "${HERMES_ROOT:-}" ]] && [[ -d "$HERMES_ROOT" ]]; then
        log_debug "HERMES_ROOT already set: $HERMES_ROOT"
        return 0
    fi

    local candidate
    for candidate in "${_hermes_candidates[@]}"; do
        [[ -z "$candidate" ]] && continue
        if _hermes_is_valid_root "$candidate"; then
            HERMES_ROOT="$candidate"
            log_debug "Resolved HERMES_ROOT: $HERMES_ROOT"
            return 0
        fi
    done

    log_error "Hermes installation not found in any known location"
    log_error "Set HERMES_ROOT or HERMES_HOME and try again"
    return "$EXIT_REPO_NOT_FOUND"
}

# Check whether a directory looks like a Hermes installation.
# Checks for the presence of at least one characteristic marker file.
_hermes_is_valid_root() {
    local dir="$1"
    [[ -d "$dir" ]] || return 1

    # A Hermes repo has .git AND at least one of these markers:
    local markers=(
        "$dir/run_agent.py"
        "$dir/hermes"
        "$dir/agent"
        "$dir/SKILL.md"
        "$dir/.hermes"
    )
    local m
    for m in "${markers[@]}"; do
        [[ -e "$m" ]] && return 0
    done

    # As a last resort, if it's a git repo, accept it.
    [[ -d "$dir/.git" ]] && return 0

    return 1
}

# Return the resolved Hermes root directory.
# Usage: hermes_root
# Returns: 0 and echoes the path, or 1 if not found.
hermes_root() {
    if [[ -z "${HERMES_ROOT:-}" ]]; then
        hermes_resolve_root || return 1
    fi
    echo "$HERMES_ROOT"
    return 0
}

# ---------------------------------------------------------------------------
# PATHS INSIDE THE HERMES INSTALLATION
# ---------------------------------------------------------------------------

# Hermes binary / CLI entry point.
# Usage: hermes_bin
hermes_bin() {
    if command -v hermes &>/dev/null; then
        command -v hermes
    elif [[ -x "${HERMES_ROOT:-}/hermes" ]]; then
        echo "${HERMES_ROOT:-}/hermes"
    elif [[ -x "${HERMES_ROOT:-}/run_agent.py" ]]; then
        echo "python3 ${HERMES_ROOT:-}/run_agent.py"
    else
        log_error "Hermes binary not found"
        return 1
    fi
}

# Hermes configuration directory.
# Usage: hermes_config_dir
hermes_config_dir() {
    local root
    root=$(hermes_root) || return 1

    # Check known config locations in order.
    local candidates=(
        "$root/.hermes"
        "$root/config"
        "$HERMES_CONFIG_DIR"
        "$ROOT/../.hermes"
        "$HOME/.hermes"
    )
    local c
    for c in "${candidates[@]}"; do
        [[ -d "$c" ]] && { echo "$c"; return 0; }
    done

    # Fall back to the env var or default.
    echo "${HERMES_DATA_DIR:-$HOME/.hermes}"
}

# Hermes data/cache directory (where backups, state, etc. live).
# Usage: hermes_data_dir
hermes_data_dir() {
    local root
    root=$(hermes_root) || return 1

    local candidates=(
        "$root/data"
        "$root/.hermes"
        "$HERMES_DATA_DIR"
        "$HOME/.hermes"
    )
    local c
    for c in "${candidates[@]}"; do
        [[ -d "$c" ]] && { echo "$c"; return 0; }
    done

    echo "${HERMES_DATA_DIR:-$HOME/.hermes}"
    return 0
}

# ---------------------------------------------------------------------------
# VERSION DETECTION
# ---------------------------------------------------------------------------

# Get the Hermes version string.
# Usage: hermes_version
# Returns: 0 and echoes the version, or 1 on failure.
hermes_version() {
    local version_output

    # Try the CLI first.
    if version_output=$(hermes version 2>/dev/null | head -1); then
        echo "$version_output"
        return 0
    fi

    # Fall back: read from a version file if one exists.
    local root
    root=$(hermes_root) || return 1

    local version_files=(
        "${root}/VERSION"
        "${root}/version"
        "${root}/.hermes/VERSION"
    )
    local vf
    for vf in "${version_files[@]}"; do
        if [[ -f "$vf" ]]; then
            cat "$vf" | head -1
            return 0
        fi
    done

    # Last resort: try to detect from git tags or commit metadata.
    if [[ -d "$root/.git" ]]; then
        local tag
        tag=$(git -C "$root" describe --tags --always 2>/dev/null) || true
        if [[ -n "$tag" ]]; then
            echo "$tag"
            return 0
        fi
    fi

    log_error "Could not determine Hermes version"
    return 1
}

# Extract a semantic version from a version string (e.g., "v1.2.3" -> "1.2.3").
# Usage: hermes_semver <version_string>
# Returns: 0 and echoes the semver portion, or 1 if not parseable.
hermes_semver() {
    local ver="${1:-}"
    # Strip leading 'v' if present, then extract X.Y.Z
    ver="${ver#v}"
    if [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        echo "${BASH_REMATCH[0]}"
        return 0
    fi
    log_error "Version string not parseable as semver: $ver"
    return 1
}

# ---------------------------------------------------------------------------
# UPDATE EXECUTION (ABSTRACTED)
# ---------------------------------------------------------------------------

# Execute Hermes update via the configured provider.
# This replaces direct calls to `hermes update` or `git pull` scattered
# across the codebase with a single abstraction point.
#
# Environment variables:
#   CONFIG_UPDATE_PROVIDER  (default: "hermes-update")
#   CONFIG_REMOTES_UPSTREAM
#
# Returns: 0 on success, non-zero on failure.
hermes_execute_update() {
    local provider="${CONFIG_UPDATE_PROVIDER:-hermes-update}"

    case "$provider" in
        hermes-update)
            log_info "Updating Hermes via hermes update..."
            if hermes update 2>&1; then
                log_info "hermes update completed successfully"
                return 0
            else
                log_error "hermes update failed"
                return 1
            fi
            ;;
        git-pull)
            local upstream="${CONFIG_REMOTES_UPSTREAM:-origin}"
            log_info "Updating Hermes via git pull $upstream main..."
            if git pull "$upstream" main 2>&1; then
                log_info "git pull completed successfully"
                return 0
            else
                log_error "git pull failed"
                return 1
            fi
            ;;
        custom)
            if [[ -n "${CONFIG_UPDATE_CUSTOM_CMD:-}" ]]; then
                log_info "Updating Hermes via custom command..."
                if eval "$CONFIG_UPDATE_CUSTOM_CMD" 2>&1; then
                    log_info "Custom update completed successfully"
                    return 0
                else
                    log_error "Custom update command failed"
                    return 1
                fi
            else
                log_error "Update provider 'custom' selected but CONFIG_UPDATE_CUSTOM_CMD is not set"
                return 1
            fi
            ;;
        *)
            log_error "Unknown update provider: $provider"
            return 1
            ;;
    esac
}

# ---------------------------------------------------------------------------
# HEALTH VERIFICATION
# ---------------------------------------------------------------------------

# Verify Hermes is healthy after an update or patch application.
# This is the single place where health checks are defined.
#
# Returns: 0 if healthy, 1 if unhealthy.
hermes_verify_healthy() {
    local root
    root=$(hermes_root) || return 1

    # Check 1: Hermes CLI responds.
    local version_output
    if ! version_output=$(hermes version 2>&1); then
        log_error "Hermes CLI failed to respond"
        return 1
    fi

    # Check 2: Output does not contain error indicators.
    if echo "$version_output" | grep -qiE '(error|traceback|exception|fatal)'; then
        log_error "Hermes version output contains error indicators: $version_output"
        return 1
    fi

    # Check 3: Hermes can start (exercise the Python environment).
    # We run hermes version which imports the CLI + Python env.
    local start_output
    if ! start_output=$(hermes version 2>&1); then
        log_error "Hermes does not start after update (version output: $start_output)"
        return 1
    fi
    if [[ -z "$start_output" ]]; then
        log_error "Hermes version output is empty"
        return 1
    fi

    log_info "Hermes health check passed: $start_output"
    return 0
}

# Check if Hermes can load its configuration.
# Returns: 0 if config loads, 1 if not.
hermes_verify_config() {
    local config_dir
    config_dir=$(hermes_config_dir) || return 1

    if [[ ! -d "$config_dir" ]]; then
        log_error "Hermes config directory not found: $config_dir"
        return 1
    fi

    log_debug "Hermes config directory: $config_dir"
    return 0
}

# ---------------------------------------------------------------------------
# CONFIGURATION INTERFACE
# ---------------------------------------------------------------------------

# Read a Hermes configuration value.
# Usage: hermes_config_get <key> [default]
# Reads from Hermes config files or environment variables.
hermes_config_get() {
    local key="$1"
    local default="${2:-}"

    # Check environment variable first.
    local env_var="HERMES_${key^^}"
    if [[ -n "${!env_var:-}" ]]; then
        echo "${!env_var}"
        return 0
    fi

    # Check Hermes config files.
    local config_dir
    config_dir=$(hermes_config_dir) 2>/dev/null || return 1

    local config_files=(
        "$config_dir/config.yaml"
        "$config_dir/config.toml"
        "$config_dir/config.json"
        "$config_dir/.env"
    )

    local cf
    for cf in "${config_files[@]}"; do
        if [[ -f "$cf" ]]; then
            local value
            value=$(grep -E "^[[:space:]]*${key}:" "$cf" 2>/dev/null | head -1 | sed "s/[^:]*:[[:space:]]*//" | tr -d '"' | tr -d "'")
            if [[ -n "$value" ]]; then
                echo "$value"
                return 0
            fi
        fi
    done

    echo "$default"
    return 0
}

# ---------------------------------------------------------------------------
# ADAPTER INITIALIZATION
# ---------------------------------------------------------------------------

# Initialize the Hermes adapter layer.
# Resolves paths and verifies Hermes is accessible.
# Returns: 0 on success, non-zero on failure.
hermes_adapter_init() {
    local errors=0

    # Resolve Hermes root.
    if ! hermes_resolve_root; then
        log_error "Hermes adapter: cannot resolve Hermes installation root"
        errors=$((errors + 1))
    fi

    # Verify Hermes is responding.
    if ! hermes_verify_healthy 2>/dev/null; then
        log_warn "Hermes adapter: health check did not pass (Hermes may not be installed)"
        # Non-fatal for adapter init — allows config-only operations.
    fi

    return $errors
}

# Export key functions for sourcing by other scripts.
export -f hermes_resolve_root hermes_root hermes_bin hermes_version
export -f hermes_semver hermes_execute_update hermes_verify_healthy
export -f hermes_adapter_init hermes_config_get hermes_config_dir hermes_data_dir