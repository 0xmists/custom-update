#!/usr/bin/env bash
# Configuration manager for the custom-update skill.
# Handles loading, saving, and validating configuration.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/logging.sh"
source "$SCRIPT_DIR/atomic.sh"
source "$SCRIPT_DIR/exit-codes.sh"

# Default configuration values
CUSTOM_CONFIG_DIR="${CUSTOM_CONFIG_DIR:-$HOME/.hermes/custom-backups}"
CUSTOM_CONFIG_FILE="${CUSTOM_CONFIG_FILE:-$CUSTOM_CONFIG_DIR/config.yaml}"

# Default config values
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

    # Source the config as bash variables
    # Simple YAML-like parsing for our config format
    local in_remotes=false
    local line key value

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        # Handle remotes section
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

        # Handle key: value pairs
        if [[ "$line" =~ ^[a-z_]+:[[:space:]]*(.+) ]]; then
            key="${line%%:*}"
            value="${BASH_REMATCH[1]//\"/}"
            # Remove leading/trailing whitespace
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
                first_run_complete) CONFIG_FIRST_RUN_COMPLETE="$value" ;;
            esac
        fi
    done < "$CUSTOM_CONFIG_FILE"

    # Apply defaults for missing values
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
    CONFIG_FIRST_RUN_COMPLETE="${CONFIG_FIRST_RUN_COMPLETE:-false}"

    return 0
}

# Save configuration to file.
# Returns: 0 on success, 1 on failure.
config_save() {
    local backup_dir
    backup_dir=$(_expand_path "${CONFIG_BACKUP_DIR:-~/.hermes/custom-backups}")
    mkdir -p "$backup_dir"

    local content
    content=$(cat <<EOF
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

update_timeout: ${CONFIG_UPDATE_TIMEOUT:-1800}

first_run_complete: ${CONFIG_FIRST_RUN_COMPLETE:-false}
EOF
)

    atomic_write "$CUSTOM_CONFIG_FILE" "$content"
    return 0
}

# Initialize configuration with defaults.
# Returns: 0 on success.
config_init() {
    local backup_dir
    backup_dir=$(_expand_path "$CONFIG_BACKUP_DIR")
    mkdir -p "$backup_dir"

    _config_defaults > "$CUSTOM_CONFIG_FILE"
    log_info "Configuration initialized at $CUSTOM_CONFIG_FILE"
    return 0
}

# Get the backup directory (expanded).
# Returns: 0 and echoes the path.
config_backup_dir() {
    _expand_path "${CONFIG_BACKUP_DIR:-~/.hermes/custom-backups}"
}

# Check if confirmation is required for destructive operations.
# Returns: 0 if confirmation required, 1 if not.
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
