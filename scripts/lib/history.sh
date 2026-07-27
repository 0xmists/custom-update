#!/usr/bin/env bash
# Operation history logger for the custom-update skill.
# Maintains an audit trail of all operations in JSON-lines format.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/logging.sh"
source "$SCRIPT_DIR/atomic.sh"

# Default history log path
CUSTOM_HISTORY_LOG="${CUSTOM_HISTORY_LOG:-$HOME/.hermes/custom-backups/history.log}"

# Log an operation to the history file.
# Usage: history_log <operation> <status> [details] [backup_id]
# Returns: 0 on success.
history_log() {
    local operation="$1"
    local status="$2"
    local details="${3:-}"
    local backup_id="${4:-}"

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Build JSON entry using jq if available, otherwise manual
    local entry
    if command -v jq &>/dev/null; then
        entry=$(jq -cn \
            --arg ts "$timestamp" \
            --arg op "$operation" \
            --arg st "$status" \
            --arg det "$details" \
            --arg bid "$backup_id" \
            '{timestamp: $ts, operation: $op, status: $st, details: $det, backup_id: $bid}')
    else
        # Manual JSON construction (escape quotes)
        details="${details//\"/\\\"}"
        entry="{\"timestamp\": \"$timestamp\", \"operation\": \"$operation\", \"status\": \"$status\", \"details\": \"$details\", \"backup_id\": \"$backup_id\"}"
    fi

    atomic_append "$CUSTOM_HISTORY_LOG" "$entry"
    log_debug "History: $operation ($status)"
}

# View recent history entries.
# Usage: history_view [--backup <backup_id>] [--last <n>]
# Returns: 0 and echoes entries.
history_view() {
    local backup_id=""
    local last_n=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --backup)
                backup_id="$2"
                shift 2
                ;;
            --last)
                last_n="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    if [[ ! -f "$CUSTOM_HISTORY_LOG" ]]; then
        log_info "No history log found"
        return 0
    fi

    local entries
    if [[ -n "$backup_id" ]]; then
        entries=$(grep "\"backup_id\": \"$backup_id\"" "$CUSTOM_HISTORY_LOG" 2>/dev/null)
    else
        entries=$(cat "$CUSTOM_HISTORY_LOG")
    fi

    if [[ -n "$last_n" ]]; then
        entries=$(echo "$entries" | tail -n "$last_n")
    fi

    if [[ -z "$entries" ]]; then
        log_info "No history entries found"
        return 0
    fi

    # Pretty-print JSON entries
    if command -v jq &>/dev/null; then
        echo "$entries" | jq -r '.timestamp + " | " + .operation + " | " + .status + " | " + .details'
    else
        echo "$entries"
    fi

    return 0
}

# Set the history log path.
# Usage: history_set_log_path <path>
history_set_log_path() {
    CUSTOM_HISTORY_LOG="$1"
}
