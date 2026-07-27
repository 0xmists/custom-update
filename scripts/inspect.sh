#!/usr/bin/env bash
# Inspect command for the custom-update skill.
# Displays detailed information about a specific backup.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

source "$LIB_DIR/exit-codes.sh"
source "$LIB_DIR/logging.sh"
source "$LIB_DIR/git-utils.sh"
source "$LIB_DIR/repo-locator.sh"
source "$LIB_DIR/config.sh"
source "$LIB_DIR/history.sh"

# Main inspect function.
inspect_main() {
    local backup_id="${1:-}"

    if [[ -z "$backup_id" ]]; then
        log_error "Usage: hermes custom inspect <BACKUP_ID>"
        return "$EXIT_GENERAL_ERROR"
    fi

    # Load config
    config_load 2>/dev/null || true

    # Find backup
    local backup_dir
    backup_dir=$(config_backup_dir)/"$backup_id"

    if [[ ! -d "$backup_dir" ]]; then
        log_error "Backup not found: $backup_id"
        return "$EXIT_BACKUP_NOT_FOUND"
    fi

    local manifest="$backup_dir/manifest.json"
    if [[ ! -f "$manifest" ]]; then
        log_error "Manifest not found for backup: $backup_id"
        return "$EXIT_GENERAL_ERROR"
    fi

    # Parse and display manifest
    echo "Backup: $backup_id"
    echo ""

    if command -v jq &>/dev/null; then
        # Use jq for parsing
        local created_at hermes_version current_commit upstream_commit patch_count bundle_size tag tag_pushed verification_status

        created_at=$(jq -r '.created_at // "unknown"' "$manifest")
        hermes_version=$(jq -r '.hermes_version // "unknown"' "$manifest")
        current_commit=$(jq -r '.current_commit // "unknown"' "$manifest")
        current_commit_short=$(jq -r '.current_commit_short // .current_commit // "unknown"' "$manifest")
        upstream_commit=$(jq -r '.upstream_commit // "unknown"' "$manifest")
        patch_count=$(jq -r '.patch_count // 0' "$manifest")
        bundle_size=$(jq -r '.bundle_size // 0' "$manifest")
        tag=$(jq -r '.tag // "unknown"' "$manifest")
        tag_pushed=$(jq -r '.tag_pushed // "false"' "$manifest")
        verification_status=$(jq -r '.verification.status // "unknown"' "$manifest")

        printf '  Created:        %s\n' "$created_at"
        printf '  Hermes version: %s\n' "$hermes_version"
        printf '  Current commit: %s (%s)\n' "$current_commit_short" "$current_commit"
        printf '  Upstream commit: %s\n' "$upstream_commit"
        printf '  Patch count:    %s\n' "$patch_count"
        printf '  Bundle size:    %s MB\n' "$((bundle_size / 1024 / 1024))"
        printf '  Tag:            %s\n' "$tag"
        printf '  Tag pushed:     %s\n' "$([[ "$tag_pushed" == "true" ]] && echo '✓ yes' || echo '✗ no')"
        printf '  Verified:       %s\n' "$verification_status"

        # List patches
        echo ""
        echo "Patches:"
        jq -r '.patch_shas[]?' "$manifest" 2>/dev/null | while read -r sha; do
            [[ -n "$sha" ]] && printf '  %s\n' "$sha"
        done

        # List modified files
        echo ""
        echo "Files modified:"
        jq -r '.files_modified[]?' "$manifest" 2>/dev/null | while read -r file; do
            [[ -n "$file" ]] && printf '  %s\n' "$file"
        done

        # List recovery methods
        echo ""
        echo "Recovery methods:"
        [[ -f "$backup_dir/backup.bundle" ]] && echo "  ✓ Git Tag         $tag"
        [[ -f "$backup_dir/backup.bundle" ]] && echo "  ✓ Git Bundle      $backup_dir/backup.bundle"
        [[ -d "$backup_dir/patches" ]] && echo "  ✓ Exported Patches $backup_dir/patches/"

        # Show verification details
        echo ""
        echo "Verification:"
        local bundle_verified patches_verified
        bundle_verified=$(jq -r '.verification.bundle_verified // "unknown"' "$manifest")
        patches_verified=$(jq -r '.verification.patches_verified // "unknown"' "$manifest")
        printf '  Bundle:    %s\n' "$bundle_verified"
        printf '  Patches:   %s\n' "$patches_verified"
        printf '  Manifest:  %s\n' "$verification_status"

    else
        # Fallback: manual parsing
        echo "  (Install jq for better formatting)"
        echo ""
        cat "$manifest"
    fi

    # Show history for this backup
    echo ""
    echo "History:"
    history_view --backup "$backup_id"

    return "$EXIT_SUCCESS"
}

# Run the inspect command
inspect_main "$@"
