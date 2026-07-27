#!/usr/bin/env bash
# List command for the custom-update skill.
# Lists all available backups.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

source "$LIB_DIR/exit-codes.sh"
source "$LIB_DIR/logging.sh"
source "$LIB_DIR/config.sh"

# List all available backups.
list_main() {
    # Load config
    config_load 2>/dev/null || true

    local backup_dir
    backup_dir=$(config_backup_dir)

    if [[ ! -d "$backup_dir" ]]; then
        log_info "No backups found (directory does not exist: $backup_dir)"
        return "$EXIT_SUCCESS"
    fi

    # Collect backup directories
    local backups=()
    while IFS= read -r dir; do
        [[ -d "$dir" ]] && backups+=("$dir")
    done < <(find "$backup_dir" -maxdepth 1 -mindepth 1 -type d | sort -r)

    if [[ ${#backups[@]} -eq 0 ]]; then
        log_info "No backups found"
        return "$EXIT_SUCCESS"
    fi

    # Print header
    printf '%-22s %-10s %-10s %-8s %-8s %-10s %s\n' \
        "ID" "Commit" "Version" "Patches" "Verified" "Methods" "Location"
    printf '%s\n' "$(printf '%.0s-' {1..120})"

    # Print each backup
    for backup_dir_path in "${backups[@]}"; do
        local backup_id
        backup_id=$(basename "$backup_dir_path")

        local manifest="$backup_dir_path/manifest.json"
        if [[ ! -f "$manifest" ]]; then
            printf '%-22s %-10s\n' "$backup_id" "no manifest"
            continue
        fi

        # Parse manifest using jq or manual parsing
        local commit version patch_count verified methods
        if command -v jq &>/dev/null; then
            commit=$(jq -r '.current_commit_short // .current_commit // "unknown"' "$manifest" 2>/dev/null | cut -c1-10)
            version=$(jq -r '.hermes_version // "unknown"' "$manifest" 2>/dev/null)
            patch_count=$(jq -r '.patch_count // 0' "$manifest" 2>/dev/null)
            verified=$(jq -r '.verification.status // "unknown"' "$manifest" 2>/dev/null)
            methods=""
            [[ -f "$backup_dir_path/backup.bundle" ]] && methods="${methods}tag "
            [[ -d "$backup_dir_path/patches" ]] && methods="${methods}patches"
        else
            commit=$(grep -o '"current_commit_short": "[^"]*"' "$manifest" 2>/dev/null | cut -d'"' -f4 | cut -c1-10)
            version=$(grep -o '"hermes_version": "[^"]*"' "$manifest" 2>/dev/null | cut -d'"' -f4)
            patch_count=$(grep -o '"patch_count": [0-9]*' "$manifest" 2>/dev/null | grep -o '[0-9]*')
            verified=$(grep -o '"status": "[^"]*"' "$manifest" 2>/dev/null | tail -1 | cut -d'"' -f4)
            methods=""
            [[ -f "$backup_dir_path/backup.bundle" ]] && methods="${methods}tag "
            [[ -d "$backup_dir_path/patches" ]] && methods="${methods}patches"
        fi

        # Format verified status
        local verified_display
        case "$verified" in
            verified) verified_display="✓" ;;
            failed) verified_display="✗" ;;
            *) verified_display="?" ;;
        esac

        printf '%-22s %-10s %-10s %-8s %-8s %-10s %s\n' \
            "$backup_id" "${commit:-unknown}" "${version:-unknown}" \
            "${patch_count:-0}" "$verified_display" "${methods:-none}" \
            "$backup_dir_path"
    done

    echo ""
    echo "Total: ${#backups[@]} backups"
    return "$EXIT_SUCCESS"
}

# Run the list command
list_main "$@"
