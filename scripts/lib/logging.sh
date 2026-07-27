#!/usr/bin/env bash
# Logging utilities for the custom-update skill.

# Log levels
LOG_LEVEL_DEBUG=0
LOG_LEVEL_INFO=1
LOG_LEVEL_WARN=2
LOG_LEVEL_ERROR=3

# Current log level (default: INFO)
CUSTOM_LOG_LEVEL="${CUSTOM_LOG_LEVEL:-$LOG_LEVEL_INFO}"

# Get current timestamp in ISO 8601 format
_log_timestamp() {
    date -u +%Y-%m-%dT%H:%M:%SZ
}

# Log a message at the given level.
# Usage: _log <level> <message>
_log() {
    local level="$1"
    local message="$2"
    local level_name
    local level_num

    case "$level" in
        debug) level_name="DEBUG"; level_num=$LOG_LEVEL_DEBUG ;;
        info)  level_name="INFO";  level_num=$LOG_LEVEL_INFO ;;
        warn)  level_name="WARN";  level_num=$LOG_LEVEL_WARN ;;
        error) level_name="ERROR"; level_num=$LOG_LEVEL_ERROR ;;
        *)     level_name="INFO";  level_num=$LOG_LEVEL_INFO ;;
    esac

    if (( level_num >= CUSTOM_LOG_LEVEL )); then
        printf '[%s] [%s] %s\n' "$(_log_timestamp)" "$level_name" "$message" >&2
    fi
}

# Convenience functions
log_debug() { _log debug "$1"; }
log_info()  { _log info  "$1"; }
log_warn()  { _log warn  "$1"; }
log_error() { _log error "$1"; }

# Print a success message (to stdout)
log_success() {
    printf '✓ %s\n' "$1"
}

# Print a failure message (to stderr)
log_failure() {
    printf '✗ %s\n' "$1" >&2
}
