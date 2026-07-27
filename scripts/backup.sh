#!/usr/bin/env bash
# Backup command for the custom-update skill.
# Wraps the backup manager (creation, reuse, cleanup).
# Uses the Hermes adapter layer for all Hermes-specific operations.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

source "$LIB_DIR/exit-codes.sh"
source "$LIB_DIR/logging.sh"
source "$LIB_DIR/git-utils.sh"
source "$LIB_DIR/hermes-adapter.sh"
source "$LIB_DIR/config.sh"
source "$LIB_DIR/repo-locator.sh"
source "$LIB_DIR/remote-detector.sh"
source "$LIB_DIR/history.sh"
source "$LIB_DIR/patch-manager.sh"
source "$LIB_DIR/bundle-manager.sh"
source "$LIB_DIR/manifest.sh"
source "$LIB_DIR/verifier.sh"
source "$LIB_DIR/update-state.sh"
source "$LIB_DIR/backup-manager.sh"

# Main backup function.
backup_main() {
    local subcommand="${1:-create}"

    case "$subcommand" in
        create)
            local new_id
            if ! new_id=$(backup_create); then
                log_error "Backup creation failed"
                return "$EXIT_GENERAL_ERROR"
            fi
            history_log "backup_created" "success" "user-initiated" "$new_id"
            return "$EXIT_SUCCESS"
            ;;
        cleanup)
            backup_cleanup
            return "$EXIT_SUCCESS"
            ;;
        *)
            log_error "Unknown backup subcommand: $subcommand"
            echo "Usage: backup.sh [create|cleanup]"
            return "$EXIT_GENERAL_ERROR"
            ;;
    esac
}

backup_main "$@"