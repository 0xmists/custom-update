#!/usr/bin/env bash
# Update state tracking for the custom-update skill.
# Persists per-update phase progress so interrupted updates can resume
# from the last completed phase without creating another backup.

BM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$BM_DIR/logging.sh"
source "$BM_DIR/atomic.sh"
source "$BM_DIR/config.sh"

# Phases tracked by the update workflow, in execution order.
# backup -> update -> apply -> verify -> publish
UPDATE_PHASES=(backup update apply verify publish)

# Resolve the state file path (lives inside the backup dir).
_update_state_file() {
    echo "$(config_backup_dir)/.update-state"
}

# Initialize a fresh update state. All phases reset to pending.
# Returns: 0 on success.
update_state_init() {
    local sf
    sf=$(_update_state_file)
    mkdir -p "$(dirname "$sf")"
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local content
    content=$(cat <<EOF
STATE_BACKUP_PHASE=pending
STATE_UPDATE_PHASE=pending
STATE_APPLY_PHASE=pending
STATE_VERIFY_PHASE=pending
STATE_PUBLISH_PHASE=pending
STATE_BACKUP_ID=
STATE_BACKUP_REUSED=false
STATE_INTERRUPTED=false
STATE_STARTED_AT=$now
STATE_UPDATED_AT=$now
EOF
)
    atomic_write "$sf" "$content"
    return 0
}

# Load the current state into STATE_* shell variables.
# Returns: 0 if a state file exists, 1 otherwise.
update_state_load() {
    local sf
    sf=$(_update_state_file)
    [[ -f "$sf" ]] || return 1
    # shellcheck disable=SC1090
    source "$sf"
    return 0
}

# Persist STATE_* variables back to disk atomically.
update_state_save() {
    local sf
    sf=$(_update_state_file)
    mkdir -p "$(dirname "$sf")"
    local content
    content=$(cat <<EOF
STATE_BACKUP_PHASE=${STATE_BACKUP_PHASE:-pending}
STATE_UPDATE_PHASE=${STATE_UPDATE_PHASE:-pending}
STATE_APPLY_PHASE=${STATE_APPLY_PHASE:-pending}
STATE_VERIFY_PHASE=${STATE_VERIFY_PHASE:-pending}
STATE_PUBLISH_PHASE=${STATE_PUBLISH_PHASE:-pending}
STATE_BACKUP_ID=${STATE_BACKUP_ID:-}
STATE_BACKUP_REUSED=${STATE_BACKUP_REUSED:-false}
STATE_INTERRUPTED=${STATE_INTERRUPTED:-false}
STATE_STARTED_AT=${STATE_STARTED_AT:-}
STATE_UPDATED_AT=${STATE_UPDATED_AT:-}
EOF
)
    atomic_write "$sf" "$content"
    return 0
}

# Set a phase status (or a named field) and persist.
# Usage: update_state_set <key> <value>
#   keys: backup | update | apply | verify | publish | backup_id | backup_reused | interrupted
update_state_set() {
    local key="$1" value="$2"
    case "$key" in
        backup)         STATE_BACKUP_PHASE="$value" ;;
        update)         STATE_UPDATE_PHASE="$value" ;;
        apply)          STATE_APPLY_PHASE="$value" ;;
        verify)         STATE_VERIFY_PHASE="$value" ;;
        publish)        STATE_PUBLISH_PHASE="$value" ;;
        backup_id)      STATE_BACKUP_ID="$value" ;;
        backup_reused)  STATE_BACKUP_REUSED="$value" ;;
        interrupted)    STATE_INTERRUPTED="$value" ;;
        *)              log_warn "update_state_set: unknown key '$key'" ;;
    esac
    STATE_UPDATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    update_state_save
}

# Get a phase status (or named field) value.
# Usage: update_state_get <key>
update_state_get() {
    local key="$1"
    case "$key" in
        backup)         echo "${STATE_BACKUP_PHASE:-pending}" ;;
        update)         echo "${STATE_UPDATE_PHASE:-pending}" ;;
        apply)          echo "${STATE_APPLY_PHASE:-pending}" ;;
        verify)         echo "${STATE_VERIFY_PHASE:-pending}" ;;
        publish)        echo "${STATE_PUBLISH_PHASE:-pending}" ;;
        backup_id)      echo "${STATE_BACKUP_ID:-}" ;;
        backup_reused)  echo "${STATE_BACKUP_REUSED:-false}" ;;
        interrupted)    echo "${STATE_INTERRUPTED:-false}" ;;
        *)              echo "" ;;
    esac
}

# Echo the first phase that is not "done" (the resume point), or empty if all done.
update_state_next_phase() {
    local p
    for p in "${UPDATE_PHASES[@]}"; do
        if [[ "$(update_state_get "$p")" != "done" ]]; then
            echo "$p"
            return 0
        fi
    done
    echo ""
    return 0
}

# Returns: 0 if every phase is "done", 1 otherwise.
update_state_all_done() {
    local p
    for p in "${UPDATE_PHASES[@]}"; do
        [[ "$(update_state_get "$p")" == "done" ]] || return 1
    done
    return 0
}

# Returns: 0 if an update state file exists, 1 otherwise.
update_state_exists() {
    [[ -f "$(_update_state_file)" ]]
}

# Remove the update state file (called after a fully completed update).
update_state_clear() {
    local sf
    sf=$(_update_state_file)
    rm -f "$sf"
    return 0
}
