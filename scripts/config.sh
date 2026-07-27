#!/usr/bin/env bash
# Config command for the custom-update skill.
# Manages skill configuration.
# Uses the Hermes adapter layer for Hermes-specific settings.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

source "$LIB_DIR/exit-codes.sh"
source "$LIB_DIR/logging.sh"
source "$LIB_DIR/git-utils.sh"
source "$LIB_DIR/hermes-adapter.sh"
source "$LIB_DIR/repo-locator.sh"
source "$LIB_DIR/config.sh"
source "$LIB_DIR/remote-detector.sh"

# Show current configuration.
_config_show() {
    config_load 2>/dev/null || true

    local hermes_root_val="not set"
    hermes_root_val="${HERMES_ROOT:-$(hermes_root 2>/dev/null || echo 'not resolved')}"

    echo "Hermes Custom Configuration"
    echo ""
    echo "Hermes:"
    printf '  Root:           %s\n' "$hermes_root_val"
    printf '  Version:        %s\n' "$(hermes_version 2>/dev/null || echo 'unknown')"
    echo ""
    echo "Remotes:"
    printf '  Upstream:       %s\n' "${CONFIG_REMOTES_UPSTREAM:-not configured}"
    printf '  Fork:           %s\n' "${CONFIG_REMOTES_FORK:-not configured}"
    echo ""
    echo "Update:"
    echo "  Provider:       ${CONFIG_UPDATE_PROVIDER:-hermes-update}"
    echo "  Timeout:        ${CONFIG_UPDATE_TIMEOUT:-1800}s"
    echo ""
    echo "Backup:"
    echo "  Directory:      $(config_backup_dir)"
    echo "  Tag prefix:     ${CONFIG_BACKUP_TAG_PREFIX:-backup/}"
    echo "  Max backups:    ${CONFIG_MAX_BACKUPS:-0} (0 = unlimited)"
    echo "  Auto cleanup:   ${CONFIG_AUTO_CLEANUP:-true}"
    echo ""
    echo "Safety:"
    echo "  Enable rerere:  ${CONFIG_ENABLE_RERERE:-true}"
    echo "  Enable stash:   ${CONFIG_ENABLE_STASH:-true}"
    echo "  Confirm destructive: ${CONFIG_CONFIRM_DESTRUCTIVE:-true}"
    echo ""
    echo "First run:      ${CONFIG_FIRST_RUN_COMPLETE:-false}"
    echo ""
    echo "Config file:    $CUSTOM_CONFIG_FILE"
}

# Auto-detect remotes and save.
_config_detect_remotes() {
    config_load 2>/dev/null || true

    # Locate and cd to Hermes repo.
    if ! locate_hermes_repo 2>/dev/null; then
        log_error "Hermes repository not found"
        return "$EXIT_REPO_NOT_FOUND"
    fi
    cd_hermes_repo || return "$EXIT_REPO_NOT_FOUND"

    echo "Auto-detecting remotes..."
    if auto_detect_remotes; then
        config_save
        log_success "Remotes configured and saved"
        return "$EXIT_SUCCESS"
    else
        log_error "Could not auto-detect remotes"
        return "$EXIT_VALIDATION_FAILURE"
    fi
}

# Set a configuration value.
_config_set() {
    local key="$1"
    local value="$2"

    config_load 2>/dev/null || true

    case "$key" in
        remotes.upstream)  CONFIG_REMOTES_UPSTREAM="$value" ;;
        remotes.fork)      CONFIG_REMOTES_FORK="$value" ;;
        update_provider)   CONFIG_UPDATE_PROVIDER="$value" ;;
        backup_dir)        CONFIG_BACKUP_DIR="$value" ;;
        backup_tag_prefix) CONFIG_BACKUP_TAG_PREFIX="$value" ;;
        max_backups)       CONFIG_MAX_BACKUPS="$value" ;;
        auto_cleanup)      CONFIG_AUTO_CLEANUP="$value" ;;
        enable_rerere)     CONFIG_ENABLE_RERERE="$value" ;;
        enable_stash)      CONFIG_ENABLE_STASH="$value" ;;
        confirm_destructive) CONFIG_CONFIRM_DESTRUCTIVE="$value" ;;
        update_timeout)    CONFIG_UPDATE_TIMEOUT="$value" ;;
        hermes_root)       CONFIG_HERMES_ROOT="$value" ;;
        hermes_config_dir) CONFIG_HERMES_CONFIG_DIR="$value" ;;
        hermes_data_dir)   CONFIG_HERMES_DATA_DIR="$value" ;;
        first_run_complete) CONFIG_FIRST_RUN_COMPLETE="$value" ;;
        *)
            log_error "Unknown config key: $key"
            log_info "Available keys: remotes.upstream, remotes.fork, update_provider, backup_dir, backup_tag_prefix, max_backups, auto_cleanup, enable_rerere, enable_stash, confirm_destructive, update_timeout, hermes_root"
            return "$EXIT_GENERAL_ERROR"
            ;;
    esac

    config_save
    log_success "Config updated: $key = $value"
    return "$EXIT_SUCCESS"
}

# Main config function.
config_main() {
    local subcommand="${1:-}"

    case "$subcommand" in
        ""|--show|show)
            _config_show
            return "$EXIT_SUCCESS"
            ;;
        detect-remotes)
            _config_detect_remotes
            return $?
            ;;
        set)
            if [[ $# -lt 3 ]]; then
                log_error "Usage: hermes custom config set <key> <value>"
                return "$EXIT_GENERAL_ERROR"
            fi
            _config_set "$2" "$3"
            return $?
            ;;
        --help|-h|help)
            echo "Usage: hermes custom config [subcommand]"
            echo ""
            echo "Subcommands:"
            echo "  (none)            Show current configuration"
            echo "  detect-remotes    Auto-detect and configure remotes"
            echo "  set <key> <val>   Set a configuration value"
            echo ""
            echo "Config keys:"
            echo "  remotes.upstream         Upstream remote name"
            echo "  remotes.fork             Fork remote name"
            echo "  update_provider          hermes-update, git-pull, or custom"
            echo "  backup_dir               Backup directory path"
            echo "  backup_tag_prefix        Tag prefix for backups"
            echo "  max_backups              Maximum backups (0 = unlimited)"
            echo "  enable_rerere            Enable git rerere (true/false)"
            echo "  enable_stash             Enable stashing (true/false)"
            echo "  confirm_destructive      Confirm destructive actions (true/false)"
            echo "  update_timeout           Timeout in seconds (0 = no timeout)"
            echo "  hermes_root              Hermes installation root path"
            return "$EXIT_SUCCESS"
            ;;
        *)
            log_error "Unknown subcommand: $subcommand"
            echo "Usage: hermes custom config [show|detect-remotes|set <key> <value>|help]"
            return "$EXIT_GENERAL_ERROR"
            ;;
    esac
}

config_main "$@"