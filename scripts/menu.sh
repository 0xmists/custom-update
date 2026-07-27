#!/usr/bin/env bash
# Interactive menu for the custom-update skill.
# This is the primary entry point — all other commands are building blocks.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# Save script dir before sourcing libs (they overwrite SCRIPT_DIR)
MENU_DIR="$SCRIPT_DIR"

source "$LIB_DIR/exit-codes.sh"
source "$LIB_DIR/logging.sh"
source "$LIB_DIR/git-utils.sh"
source "$LIB_DIR/repo-locator.sh"
source "$LIB_DIR/config.sh"
source "$LIB_DIR/history.sh"
source "$LIB_DIR/remote-detector.sh"
source "$LIB_DIR/manifest.sh"
source "$LIB_DIR/update-state.sh"
source "$LIB_DIR/backup-manager.sh"

# Colors
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_RED='\033[0;31m'
C_CYAN='\033[0;36m'
C_DIM='\033[2m'

# Script paths
DOCTOR_SH="$MENU_DIR/doctor.sh"
BACKUP_SH="$MENU_DIR/backup.sh"
UPDATE_SH="$MENU_DIR/update.sh"
APPLY_SH="$MENU_DIR/apply.sh"
RESTORE_SH="$MENU_DIR/restore.sh"
LIST_SH="$MENU_DIR/list.sh"
STATUS_SH="$MENU_DIR/status.sh"
DIFF_SH="$MENU_DIR/diff.sh"
INSPECT_SH="$MENU_DIR/inspect.sh"
HISTORY_SH="$MENU_DIR/history.sh"
CONFIG_SH="$MENU_DIR/config.sh"

# Check if a verified backup exists.
# Returns 0 and echoes backup_id if found, 1 otherwise.
_has_verified_backup() {
    local backup_dir
    backup_dir=$(config_backup_dir 2>/dev/null)
    [[ -d "$backup_dir" ]] || return 1

    local latest=""
    local latest_time=0
    for dir in "$backup_dir"/*/; do
        [[ -d "$dir" ]] || continue
        local manifest="${dir}manifest.json"
        [[ -f "$manifest" ]] || continue
        if grep -q '"status": "verified"' "$manifest" 2>/dev/null; then
            local created
            created=$(grep '"created_at"' "$manifest" | sed 's/.*: *"\([^"]*\)".*/\1/')
            local timestamp
            timestamp=$(date -d "$created" +%s 2>/dev/null || echo 0)
            if (( timestamp > latest_time )); then
                latest_time=$timestamp
                latest=$(basename "$dir")
            fi
        fi
    done

    if [[ -n "$latest" ]]; then
        echo "$latest"
        return 0
    fi
    return 1
}

# Get current Hermes version string.
_get_version() {
    hermes version 2>/dev/null | head -1 || echo "unknown"
}

# Get latest verified backup ID.
_get_latest_backup() {
    local bid
    if bid=$(_has_verified_backup 2>/dev/null); then
        echo "$bid"
    else
        echo "none"
    fi
}

# Get repo health status.
_get_repo_health() {
    if locate_hermes_repo 2>/dev/null; then
        echo -e "${C_GREEN}✓ Healthy${C_RESET}"
    else
        echo -e "${C_RED}✗ Not found${C_RESET}"
    fi
}

# Clear screen (works on most terminals).
_clear() {
    clear 2>/dev/null || printf '\n%.0s' {1..50}
}

# Display the main menu header.
_show_header() {
    _clear
    echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    echo -e "${C_BOLD}Hermes Custom Update v1.0.0${C_RESET}"
    echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    echo ""
    echo "Repository:  $(_get_repo_health)"
    echo "Version:     $(_get_version)"
    echo "Backup:      $(_get_latest_backup)"
    # Show resume state if an update is in progress.
    if update_state_exists 2>/dev/null; then
        if update_state_load 2>/dev/null; then
            local _next
            _next=$(update_state_next_phase 2>/dev/null)
            if [[ -n "$_next" ]]; then
                echo "Resume:      $_next (interrupted update in progress)"
            fi
        fi
    fi
    echo ""
    echo "Choose an action:"
    echo ""
}

# Display the main menu.
_show_menu() {
    echo -e " ${C_BOLD}[1]${C_RESET} Update Hermes (Recommended)"
    echo "    Backup → Update → Apply → Verify → Publish"
    echo ""
    echo -e " ${C_BOLD}[2]${C_RESET} Create Backup"
    echo ""
    echo -e " ${C_BOLD}[3]${C_RESET} Restore Previous Version"
    echo ""
    echo -e " ${C_BOLD}[4]${C_RESET} Status"
    echo ""
    echo -e " ${C_BOLD}[5]${C_RESET} Show Changes (Diff)"
    echo ""
    echo -e " ${C_BOLD}[6]${C_RESET} List Backups"
    echo ""
    echo -e " ${C_BOLD}[7]${C_RESET} Inspect Backup"
    echo ""
    echo -e " ${C_BOLD}[8]${C_RESET} Doctor (Environment Check)"
    echo ""
    echo -e " ${C_BOLD}[9]${C_RESET} Settings"
    echo ""
    echo -e " ${C_BOLD}[10]${C_RESET} Clean Up Backups"
    echo ""
    echo -e " ${C_BOLD}[0]${C_RESET} Exit"
    echo ""
    printf "Enter your choice: "
}

# Option 1: Full phase-based update workflow.
# Delegates to update.sh which implements the 5-phase workflow:
# Backup -> Update -> Apply -> Verify -> Publish.
# Supports resume from the last incomplete phase.
_do_update() {
    _clear
    echo -e "${C_BOLD}=== Phase-Based Update Workflow ===${C_RESET}"
    echo ""

    # Check for resume state.
    local resume_msg=""
    if update_state_exists 2>/dev/null; then
        if update_state_load 2>/dev/null; then
            local _next
            _next=$(update_state_next_phase 2>/dev/null)
            if [[ -n "$_next" ]]; then
                resume_msg=" (resuming from: $_next)"
            fi
        fi
    fi
    echo "Running 5-phase workflow: Backup -> Update -> Apply -> Verify -> Publish"
    echo "Custom patches are applied ONLY after upstream update + dependency installation complete."
    echo ""
    if [[ -n "$resume_msg" ]]; then
        echo -e "${C_YELLOW}⚠ Resuming interrupted update${resume_msg}${C_RESET}"
        echo ""
    fi

    echo "This may take several minutes (dependency installation, Rust/C compilation)."
    echo "Please wait..."
    echo ""

    # Get configurable timeout (default 30 minutes = 1800 seconds)
    local timeout_secs="${CONFIG_UPDATE_TIMEOUT:-1800}"

    # Run the phase-based update with configurable timeout.
    local update_output
    local update_exit=0
    update_output=$(timeout "$timeout_secs" bash "$UPDATE_SH" 2>&1) || update_exit=$?

    echo "$update_output"

    if [[ $update_exit -eq 0 ]]; then
        echo ""
        echo -e "${C_GREEN}✓ Update workflow complete (all 5 phases)${C_RESET}"
        echo ""
        echo -e "${C_BOLD}=== Final Status ===${C_RESET}"
        echo ""
        bash "$STATUS_SH" 2>&1
        echo ""
        echo -e "${C_BOLD}=== Changes ===${C_RESET}"
        echo ""
        bash "$DIFF_SH" 2>&1
        echo ""
    elif [[ $update_exit -eq 124 ]]; then
        echo ""
        echo -e "${C_YELLOW}⚠ Update timed out after $timeout_secs seconds${C_RESET}"
        echo "The update may still be running. State has been saved for resume."
        echo "Run option 1 again to resume from the last completed phase."
        echo "Your backup is safe. Run option 3 to restore if needed."
    else
        echo ""
        echo -e "${C_RED}✗ Update workflow failed (exit $update_exit)${C_RESET}"
        echo "The workflow aborted at the failing phase. State has been saved for resume."
        echo "Run option 1 again to resume from the last completed phase."
        echo "Your backup is safe. Run option 3 to restore if needed."
    fi
    echo ""
    _wait_for_enter
}

# Option 2: Create backup.
_do_backup() {
    _clear
    echo -e "${C_BOLD}=== Create Backup ===${C_RESET}"
    echo ""
    bash "$BACKUP_SH" 2>&1
    echo ""
    _wait_for_enter
}

# Option 3: Restore with backup selection.
_do_restore() {
    _clear
    echo -e "${C_BOLD}=== Restore Previous Version ===${C_RESET}"
    echo ""

    # Get list of verified backups
    local backup_dir
    backup_dir=$(config_backup_dir 2>/dev/null)
    if [[ ! -d "$backup_dir" ]]; then
        echo -e "${C_YELLOW}No backups found.${C_RESET}"
        _wait_for_enter
        return
    fi

    # Collect verified backups
    local backups=()
    local i=1
    echo "Available backups:"
    echo ""
    for dir in "$backup_dir"/*/; do
        [[ -d "$dir" ]] || continue
        local manifest="${dir}manifest.json"
        [[ -f "$manifest" ]] || continue
        local bid
        bid=$(basename "$dir")
        local verified="✗"
        if grep -q '"status": "verified"' "$manifest" 2>/dev/null; then
            verified="✓"
        fi
        local created
        created=$(grep '"created_at"' "$manifest" | sed 's/.*: *"\([^"]*\)".*/\1/' 2>/dev/null || echo "?")
        local patches
        patches=$(grep '"patch_count"' "$manifest" | grep -o '[0-9]*' || echo "?")
        echo "  [$i] $bid $verified  ($patches patches, $created)"
        backups+=("$bid")
        i=$((i + 1))
    done

    if [[ ${#backups[@]} -eq 0 ]]; then
        echo ""
        echo -e "${C_YELLOW}No backups found.${C_RESET}"
        _wait_for_enter
        return
    fi

    echo ""
    printf "Select a backup to restore (1-$((i-1))): "
    local choice
    read -r choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#backups[@]} )); then
        local selected="${backups[$((choice - 1))]}"
        echo ""
        echo "Restoring from: $selected"
        echo ""
        if bash "$RESTORE_SH" "$selected" --auto-confirm 2>&1; then
            echo -e "${C_GREEN}✓ Restore completed${C_RESET}"
        else
            echo -e "${C_RED}✗ Restore failed${C_RESET}"
        fi
    else
        echo -e "${C_YELLOW}Invalid selection.${C_RESET}"
    fi
    echo ""
    _wait_for_enter
}

# Option 4: Status.
_do_status() {
    _clear
    echo -e "${C_BOLD}=== Status ===${C_RESET}"
    echo ""
    bash "$STATUS_SH" 2>&1
    echo ""
    _wait_for_enter
}

# Option 5: Diff.
_do_diff() {
    _clear
    echo -e "${C_BOLD}=== Show Changes (Diff) ===${C_RESET}"
    echo ""
    bash "$DIFF_SH" 2>&1
    echo ""
    _wait_for_enter
}

# Option 6: List backups.
_do_list() {
    _clear
    echo -e "${C_BOLD}=== List Backups ===${C_RESET}"
    echo ""
    bash "$LIST_SH" 2>&1
    echo ""
    _wait_for_enter
}

# Option 7: Inspect backup.
_do_inspect() {
    _clear
    echo -e "${C_BOLD}=== Inspect Backup ===${C_RESET}"
    echo ""

    # Try to get latest backup
    local latest
    latest=$(_has_verified_backup 2>/dev/null || echo "")
    if [[ -n "$latest" ]]; then
        printf "Press Enter to inspect latest backup ($latest), or enter a backup ID: "
    else
        printf "Enter backup ID: "
    fi
    local bid
    read -r bid

    if [[ -z "$bid" ]]; then
        if [[ -n "$latest" ]]; then
            bid="$latest"
        else
            echo -e "${C_YELLOW}No backup ID provided.${C_RESET}"
            _wait_for_enter
            return
        fi
    fi

    echo ""
    bash "$INSPECT_SH" "$bid" 2>&1
    echo ""
    _wait_for_enter
}

# Option 8: Doctor.
_do_doctor() {
    _clear
    echo -e "${C_BOLD}=== Doctor (Environment Check) ===${C_RESET}"
    echo ""
    bash "$DOCTOR_SH" 2>&1
    echo ""
    _wait_for_enter
}

# Option 10: Clean Up Backups (retention policy).
_do_cleanup() {
    _clear
    echo -e "${C_BOLD}=== Clean Up Backups ===${C_RESET}"
    echo ""
    echo "Applying retention policy..."
    echo "  - Keeps the newest verified backup"
    echo "  - Keeps backups referenced by interrupted updates"
    echo "  - Keeps unverified or failed backups"
    echo "  - Removes old verified backups beyond max_backups"
    echo ""
    bash "$BACKUP_SH" cleanup 2>&1
    echo ""
    _wait_for_enter
}

# Settings submenu.
_do_settings() {
    while true; do
        _clear
        echo -e "${C_BOLD}=== Settings ===${C_RESET}"
        echo ""
        echo "  [1] Detect Remotes"
        echo "  [2] Change Update Provider"
        echo "  [3] Toggle Backup Tag Push"
        echo "  [4] Change Backup Location"
        echo "  [5] Show Current Configuration"
        echo "  [6] Change Update Timeout"
        echo "  [7] Toggle Auto Cleanup"
        echo "  [8] Change Max Backups"
        echo ""
        echo "  [0] Return to Main Menu"
        echo ""
        printf "Enter your choice: "

        local choice
        read -r choice

        case "$choice" in
            1)
                _clear
                echo -e "${C_BOLD}=== Detect Remotes ===${C_RESET}"
                echo ""
                echo "y" | bash "$CONFIG_SH" detect-remotes 2>&1
                echo ""
                _wait_for_enter
                ;;
            2)
                _clear
                echo -e "${C_BOLD}=== Change Update Provider ===${C_RESET}"
                echo ""
                echo "Available providers:"
                echo "  [1] hermes-update (uses 'hermes update')"
                echo "  [2] git-pull (uses 'git pull')"
                echo ""
                printf "Select provider (1-2): "
                local prov_choice
                read -r prov_choice
                local provider=""
                case "$prov_choice" in
                    1) provider="hermes-update" ;;
                    2) provider="git-pull" ;;
                    *) echo -e "${C_YELLOW}Invalid choice.${C_RESET}"; _wait_for_enter; continue ;;
                esac
                config_load 2>/dev/null || true
                CONFIG_UPDATE_PROVIDER="$provider"
                config_save
                echo -e "${C_GREEN}✓ Update provider set to: $provider${C_RESET}"
                _wait_for_enter
                ;;
            3)
                _clear
                echo -e "${C_BOLD}=== Toggle Backup Tag Push ===${C_RESET}"
                echo ""
                config_load 2>/dev/null || true
                local current="${CONFIG_PUSH_TAGS:-true}"
                local new="true"
                if [[ "$current" == "true" ]]; then
                    new="false"
                fi
                CONFIG_PUSH_TAGS="$new"
                config_save
                if [[ "$new" == "true" ]]; then
                    echo -e "${C_GREEN}✓ Backup tags will be pushed to fork${C_RESET}"
                else
                    echo -e "${C_GREEN}✓ Backup tags will NOT be pushed to fork${C_RESET}"
                fi
                _wait_for_enter
                ;;
            4)
                _clear
                echo -e "${C_BOLD}=== Change Backup Location ===${C_RESET}"
                echo ""
                config_load 2>/dev/null || true
                local current_dir
                current_dir=$(config_backup_dir 2>/dev/null)
                echo "Current backup location: $current_dir"
                echo ""
                printf "Enter new backup location (or press Enter to cancel): "
                local new_dir
                read -r new_dir
                if [[ -n "$new_dir" ]]; then
                    # Expand ~
                    new_dir="${new_dir/#\~/$HOME}"
                    if [[ ! -d "$new_dir" ]]; then
                        mkdir -p "$new_dir" 2>/dev/null
                    fi
                    if [[ -d "$new_dir" ]]; then
                        CONFIG_BACKUP_DIR="$new_dir"
                        config_save
                        echo -e "${C_GREEN}✓ Backup location set to: $new_dir${C_RESET}"
                    else
                        echo -e "${C_RED}✗ Directory could not be created: $new_dir${C_RESET}"
                    fi
                fi
                _wait_for_enter
                ;;
            5)
                _clear
                echo -e "${C_BOLD}=== Current Configuration ===${C_RESET}"
                echo ""
                bash "$CONFIG_SH" 2>&1
                echo ""
                _wait_for_enter
                ;;
            6)
                _clear
                echo -e "${C_BOLD}=== Change Update Timeout ===${C_RESET}"
                echo ""
                config_load 2>/dev/null || true
                local current_timeout="${CONFIG_UPDATE_TIMEOUT:-1800}"
                echo "Current timeout: $current_timeout seconds (30 minutes)"
                echo ""
                printf "Enter new timeout in seconds (300-7200, 0 for unlimited): "
                local new_timeout
                read -r new_timeout
                if [[ "$new_timeout" =~ ^[0-9]+$ ]]; then
                    if (( new_timeout >= 300 && new_timeout <= 7200 )); then
                        CONFIG_UPDATE_TIMEOUT="$new_timeout"
                        config_save
                        echo -e "${C_GREEN}✓ Update timeout set to: $new_timeout seconds${C_RESET}"
                    elif (( new_timeout == 0 )); then
                        CONFIG_UPDATE_TIMEOUT="0"
                        config_save
                        echo -e "${C_GREEN}✓ Update timeout set to: unlimited${C_RESET}"
                    else
                        echo -e "${C_YELLOW}Timeout must be between 300 and 7200 seconds (or 0 for unlimited).${C_RESET}"
                    fi
                else
                    echo -e "${C_YELLOW}Invalid input.${C_RESET}"
                fi
                echo ""
                _wait_for_enter
                ;;
            7)
                _clear
                echo -e "${C_BOLD}=== Toggle Auto Cleanup ===${C_RESET}"
                echo ""
                config_load 2>/dev/null || true
                local current_ac="${CONFIG_AUTO_CLEANUP:-true}"
                local new_ac="true"
                if [[ "$current_ac" == "true" ]]; then
                    new_ac="false"
                fi
                CONFIG_AUTO_CLEANUP="$new_ac"
                config_save
                if [[ "$new_ac" == "true" ]]; then
                    echo -e "${C_GREEN}✓ Auto cleanup enabled (old verified backups removed after update)${C_RESET}"
                else
                    echo -e "${C_GREEN}✓ Auto cleanup disabled (backups retained)${C_RESET}"
                fi
                _wait_for_enter
                ;;
            8)
                _clear
                echo -e "${C_BOLD}=== Change Max Backups ===${C_RESET}"
                echo ""
                config_load 2>/dev/null || true
                local current_mb="${CONFIG_MAX_BACKUPS:-0}"
                echo "Current max_backups: $current_mb (0 = unlimited)"
                echo ""
                printf "Enter max verified backups to keep (0 = unlimited): "
                local new_mb
                read -r new_mb
                if [[ "$new_mb" =~ ^[0-9]+$ ]]; then
                    CONFIG_MAX_BACKUPS="$new_mb"
                    config_save
                    if [[ "$new_mb" == "0" ]]; then
                        echo -e "${C_GREEN}✓ Max backups set to: unlimited${C_RESET}"
                    else
                        echo -e "${C_GREEN}✓ Max backups set to: $new_mb${C_RESET}"
                    fi
                else
                    echo -e "${C_YELLOW}Invalid input. Must be a non-negative number.${C_RESET}"
                fi
                echo ""
                _wait_for_enter
                ;;
            0)
                break
                ;;
            *)
                echo -e "${C_YELLOW}Invalid choice.${C_RESET}"
                sleep 1
                ;;
        esac
    done
}

# Wait for user to press Enter.
_wait_for_enter() {
    echo ""
    printf "Press Enter to continue... "
    read -r _
}

# Main menu loop.
main() {
    # Load config
    config_load 2>/dev/null || true

    while true; do
        _show_header
        _show_menu

        local choice
        read -r choice

        case "$choice" in
            1) _do_update ;;
            2) _do_backup ;;
            3) _do_restore ;;
            4) _do_status ;;
            5) _do_diff ;;
            6) _do_list ;;
            7) _do_inspect ;;
            8) _do_doctor ;;
            9) _do_settings ;;
            10) _do_cleanup ;;
            0)
                _clear
                echo -e "${C_GREEN}Goodbye!${C_RESET}"
                exit 0
                ;;
            *)
                echo -e "${C_YELLOW}Invalid choice. Please enter a number 0-10.${C_RESET}"
                sleep 1
                ;;
        esac
    done
}

main "$@"
