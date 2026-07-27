#!/usr/bin/env bash
# Configuration manager for the custom-update skill.
# Handles loading, saving, and validating configuration.
# All Hermes-specific paths are delegated to the Hermes adapter.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/logging.sh"
source "$SCRIPT_DIR/atomic.sh"
source "$SCRIPT_DIR/exit-codes.sh"
# Note: hermes-adapter.sh is a heavyweight dependency (resolves paths, checks Hermes installation).
# Config loading is lightweight and does not need the adapter.
# The adapter is sourced by callers that need Hermes-specific operations.

# Default configuration values (overridable via env vars).
CUSTOM_CONFIG_DIR="${CUSTOM_CONFIG_DIR:-${HERMES_DATA_DIR:-$HOME/.hermes}/custom-backups}"
CUSTOM_CONFIG_FILE="${CUSTOM_CONFIG_FILE:-$CUSTOM_CONFIG_DIR/config.yaml}"

# Default config values.
_config_defaults() {
    cat <<'EOF'
# Hermes Custom Skill Configuration
# Version: 1.0.0

# Remote names (auto-detected on first run)
remotes:
  upstream: ""
  fork: ""

# Update provider: hermes-update, git-pull, or custom
update_provider: "hermes-update"

# Backup settings
backup_dir: "~/.hermes/custom-backups"
backup_tag_prefix: "backup/"
max_backups: 0  # 0 = unlimited
auto_cleanup: true  # auto-remove old verified backups after a successful update
enable_rerere: true
enable_stash: true
confirm_destructive: true

# Hermes adapter paths (auto-detected; override if needed)
hermes_root: ""
hermes_config_dir: ""
hermes_data_dir: ""

# Update timeout in seconds (0 = no timeout)
update_timeout: 1800

# First-run state
first_run_complete: false
EOF
}

# Expand ~ in a path.
_expand_path() {
    local path="$1"
    echo "${path/#\~/$HOME}"
}

# Load configuration from file.
# Returns: 0 on success, 1 if config doesn't exist (uses defaults).
config_load() {
    if [[ ! -f "$CUSTOM_CONFIG_FILE" ]]; then
        log_debug "Config file not found, using defaults"
        return 1
    fi

    # Simple YAML-like parsing for our config format.
    local in_remotes=false line key value

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        if [[ "$line" =~ ^remotes: ]]; then
            in_remotes=true
            continue
        fi

        if [[ "$in_remotes" == true ]]; then
            if [[ "$line" =~ ^[[:space:]]+upstream:[[:space:]]*(.+) ]]; then
                CONFIG_REMOTES_UPSTREAM="${BASH_REMATCH[1]//\"/}"
            elif [[ "$line" =~ ^[[:space:]]+fork:[[:space:]]*(.+) ]]; then
                CONFIG_REMOTES_FORK="${BASH_REMATCH[1]//\"/}"
            elif [[ ! "$line" =~ ^[[:space:]] ]]; then
                in_remotes=false
            fi
            continue
        fi

        if [[ "$line" =~ ^[a-z_]+:[[:space:]]*(.+) ]]; then
            key="${line%%:*}"
            value="${BASH_REMATCH[1]//\"/}"
            value="${value#"${value%%[![:space:]]*}"}"
            value="${value%"${value##*[![:space:]]}"}"

            case "$key" in
                update_provider) CONFIG_UPDATE_PROVIDER="$value" ;;
                backup_dir) CONFIG_BACKUP_DIR="$value" ;;
                backup_tag_prefix) CONFIG_BACKUP_TAG_PREFIX="$value" ;;
                max_backups) CONFIG_MAX_BACKUPS="$value" ;;
                auto_cleanup) CONFIG_AUTO_CLEANUP="$value" ;;
                enable_rerere) CONFIG_ENABLE_RERERE="$value" ;;
                enable_stash) CONFIG_ENABLE_STASH="$value" ;;
                confirm_destructive) CONFIG_CONFIRM_DESTRUCTIVE="$value" ;;
                update_timeout) CONFIG_UPDATE_TIMEOUT="$value" ;;
                hermes_root) CONFIG_HERMES_ROOT="$value" ;;
                hermes_config_dir) CONFIG_HERMES_CONFIG_DIR="$value" ;;
                hermes_data_dir) CONFIG_HERMES_DATA_DIR="$value" ;;
                first_run_complete) CONFIG_FIRST_RUN_COMPLETE="$value" ;;
            esac
        fi
    done < "$CUSTOM_CONFIG_FILE"

    # Apply defaults for missing values.
    CONFIG_REMOTES_UPSTREAM="${CONFIG_REMOTES_UPSTREAM:-}"
    CONFIG_REMOTES_FORK="${CONFIG_REMOTES_FORK:-}"
    CONFIG_UPDATE_PROVIDER="${CONFIG_UPDATE_PROVIDER:-hermes-update}"
    CONFIG_BACKUP_DIR="${CONFIG_BACKUP_DIR:-~/.hermes/custom-backups}"
    CONFIG_BACKUP_TAG_PREFIX="${CONFIG_BACKUP_TAG_PREFIX:-backup/}"
    CONFIG_MAX_BACKUPS="${CONFIG_MAX_BACKUPS:-0}"
    CONFIG_AUTO_CLEANUP="${CONFIG_AUTO_CLEANUP:-true}"
    CONFIG_ENABLE_RERERE="${CONFIG_ENABLE_RERERE:-true}"
    CONFIG_ENABLE_STASH="${CONFIG_ENABLE_STASH:-true}"
    CONFIG_CONFIRM_DESTRUCTIVE="${CONFIG_CONFIRM_DESTRUCTIVE:-true}"
    CONFIG_UPDATE_TIMEOUT="${CONFIG_UPDATE_TIMEOUT:-1800}"
    CONFIG_HERMES_ROOT="${CONFIG_HERMES_ROOT:-}"
    CONFIG_HERMES_CONFIG_DIR="${CONFIG_HERMES_CONFIG_DIR:-}"
    CONFIG_HERMES_DATA_DIR="${CONFIG_HERMES_DATA_DIR:-}"
    CONFIG_FIRST_RUN_COMPLETE="${CONFIG_FIRST_RUN_COMPLETE:-false}"

    return 0
}

# Save configuration to file.
config_save() {
    local backup_dir
    backup_dir=$(_expand_path "${CONFIG_BACKUP_DIR:-~/.hermes/custom-backups}")
    mkdir -p "$backup_dir"

    cat >"$CUSTOM_CONFIG_FILE" <<EOF
# Hermes Custom Skill Configuration
# Version: 1.0.0

remotes:
  upstream: "${CONFIG_REMOTES_UPSTREAM:-}"
  fork: "${CONFIG_REMOTES_FORK:-}"

update_provider: "${CONFIG_UPDATE_PROVIDER:-hermes-update}"

backup_dir: "${CONFIG_BACKUP_DIR:-~/.hermes/custom-backups}"
backup_tag_prefix: "${CONFIG_BACKUP_TAG_PREFIX:-backup/}"
max_backups: ${CONFIG_MAX_BACKUPS:-0}
auto_cleanup: ${CONFIG_AUTO_CLEANUP:-true}
enable_rerere: ${CONFIG_ENABLE_RERERE:-true}
enable_stash: ${CONFIG_ENABLE_STASH:-true}
confirm_destructive: ${CONFIG_CONFIRM_DESTRUCTIVE:-true}

hermes_root: "${CONFIG_HERMES_ROOT:-}"
hermes_config_dir: "${CONFIG_HERMES_CONFIG_DIR:-}"
hermes_data_dir: "${CONFIG_HERMES_DATA_DIR:-}"

update_timeout: ${CONFIG_UPDATE_TIMEOUT:-1800}

first_run_complete: ${CONFIG_FIRST_RUN_COMPLETE:-false}
EOF
    return 0
}

# Initialize configuration with defaults.
config_init() {
    local backup_dir
    backup_dir=$(_expand_path "${CONFIG_BACKUP_DIR:-$HOME/.hermes/custom-backups}")
    mkdir -p "$backup_dir"

    _config_defaults >"$CUSTOM_CONFIG_FILE"
    log_info "Configuration initialized at $CUSTOM_CONFIG_FILE"
    return 0
}

# Get the backup directory (expanded).
config_backup_dir() {
    _expand_path "${CONFIG_BACKUP_DIR:-~/.hermes/custom-backups}"
}

# Check if confirmation is required for destructive operations.
config_confirm_required() {
    [[ "${CONFIG_CONFIRM_DESTRUCTIVE:-true}" == "true" ]]
}

# Prompt for confirmation.
# Usage: config_confirm <message>
# Returns: 0 if confirmed, 1 if not.
config_confirm() {
    local message="$1"

    if ! config_confirm_required; then
        return 0
    fi

    local response
    printf '%s [y/N] ' "$message"
    read -r response
    [[ "${response,,}" == "y" || "${response,,}" == "yes" ]]
}