#!/usr/bin/env bash
# History command for the custom-update skill.
# Displays the operation history log.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

source "$LIB_DIR/exit-codes.sh"
source "$LIB_DIR/logging.sh"
source "$LIB_DIR/config.sh"
source "$LIB_DIR/history.sh"

# Main history function.
history_main() {
    # Load config to get backup dir
    config_load 2>/dev/null || true

    # Set history log path
    local backup_dir
    backup_dir=$(config_backup_dir)
    history_set_log_path "$backup_dir/history.log"

    # Parse arguments
    local backup_id=""
    local last_n=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --backup)
                backup_id="$2"
                shift 2
                ;;
            --last|-n)
                last_n="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: hermes custom history [--backup <BACKUP_ID>] [--last <N>]"
                echo ""
                echo "Options:"
                echo "  --backup <ID>   Show history for a specific backup"
                echo "  --last <N>      Show only the last N entries"
                echo "  --help          Show this help"
                return "$EXIT_SUCCESS"
                ;;
            *)
                echo "Unknown option: $1"
                echo "Usage: hermes custom history [--backup <BACKUP_ID>] [--last <N>]"
                return "$EXIT_GENERAL_ERROR"
                ;;
        esac
    done

    # Build arguments for history_view
    local view_args=()
    [[ -n "$backup_id" ]] && view_args+=("--backup" "$backup_id")
    [[ -n "$last_n" ]] && view_args+=("--last" "$last_n")

    # Show history
    history_view "${view_args[@]}"

    return "$EXIT_SUCCESS"
}

# Run the history command
history_main "$@"
