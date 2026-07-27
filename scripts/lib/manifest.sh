#!/usr/bin/env bash
# Manifest manager for the custom-update skill.
# Handles creating and parsing backup manifests.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/logging.sh"
source "$SCRIPT_DIR/atomic.sh"
source "$SCRIPT_DIR/git-utils.sh"

# Create a manifest for a backup.
# Usage: manifest_create <backup_dir> <backup_id> <base_ref> <patch_count> <bundle_size>
# Returns: 0 on success, 1 on failure.
manifest_create() {
    local backup_dir="$1"
    local backup_id="$2"
    local base_ref="$3"
    local patch_count="$4"
    local bundle_size="$5"

    local current_commit
    current_commit=$(git_current_commit)
    local current_commit_short
    current_commit_short=$(git_current_commit_short)

    local upstream_commit
    upstream_commit=$(git_merge_base "${CONFIG_REMOTES_UPSTREAM:-origin}/main" HEAD 2>/dev/null || echo "")
    if [[ -z "$upstream_commit" ]]; then
        upstream_commit=$(git_merge_base "${CONFIG_REMOTES_FORK:-fork}/main" HEAD 2>/dev/null || echo "")
    fi

    local hermes_version
    hermes_version=$(hermes version 2>/dev/null | head -1 || echo "unknown")

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # State fingerprint for backup reuse detection (head|shas|version).
    local state_fp=""
    state_fp=$(backup_compute_fingerprint 2>/dev/null || echo "")
    [[ -z "$state_fp" ]] && state_fp="unknown"

    # Get patch SHAs
    local patch_shas=""
    if [[ -n "$base_ref" ]]; then
        patch_shas=$(git_commits_between "$base_ref" HEAD)
    fi

    # Get modified files
    local files_modified=""
    if [[ -n "$base_ref" ]]; then
        files_modified=$(git diff --name-only "$base_ref" HEAD 2>/dev/null || echo "")
    fi

    # Build patch files list
    local patch_files=""
    if [[ -d "$backup_dir/patches" ]]; then
        patch_files=$(find "$backup_dir/patches" -name '*.patch' -exec basename {} \; | sort)
    fi

    local manifest_path="$backup_dir/manifest.json"
    local content
    content=$(cat <<EOF
{
  "skill_version": "1.0.0",
  "manifest_version": "1.0",
  "backup_id": "$backup_id",
  "created_at": "$timestamp",
  "hermes_version": "$hermes_version",
  "current_commit": "$current_commit",
  "current_commit_short": "$current_commit_short",
  "state_fingerprint": "$state_fp",
  "upstream_commit": "$upstream_commit",
  "upstream_branch": "main",
  "upstream_remote": "${CONFIG_REMOTES_UPSTREAM:-origin}",
  "fork_remote": "${CONFIG_REMOTES_FORK:-fork}",
  "base_commit": "$base_ref",
  "patch_count": $patch_count,
  "patch_shas": [
$(echo "$patch_shas" | while read -r sha; do
    [[ -n "$sha" ]] && echo "    \"$sha\","
done | sed '$ s/,$//')
  ],
  "patch_files": [
$(echo "$patch_files" | while read -r pf; do
    [[ -n "$pf" ]] && echo "    \"$pf\","
done | sed '$ s/,$//')
  ],
  "files_modified": [
$(echo "$files_modified" | while read -r fm; do
    [[ -n "$fm" ]] && echo "    \"$fm\","
done | sed '$ s/,$//')
  ],
  "bundle_file": "backup.bundle",
  "bundle_size": $bundle_size,
  "tag": "backup/$backup_id",
  "tag_pushed": false,
  "stash_included": false,
  "git_rerere_enabled": true,
  "verification": {
    "status": "pending",
    "bundle_verified": false,
    "patches_verified": false,
    "manifest_verified": false,
    "verified_at": ""
  }
}
EOF
)

    atomic_write "$manifest_path" "$content"
    log_info "Manifest created: $manifest_path"
    return 0
}

# Update manifest verification status.
# Usage: manifest_update_verification <backup_dir> <status> <bundle_ok> <patches_ok>
manifest_update_verification() {
    local backup_dir="$1"
    local status="$2"
    local bundle_ok="$3"
    local patches_ok="$4"
    local manifest_path="$backup_dir/manifest.json"

    if [[ ! -f "$manifest_path" ]]; then
        return 1
    fi

    local verified_at
    verified_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Simple sed replacement for verification block
    local content
    content=$(cat "$manifest_path")

    # Replace verification status
    content=$(echo "$content" | sed "s/\"status\": \"[^\"]*\"/\"status\": \"$status\"/" | \
        sed "s/\"bundle_verified\": [a-z]*/\"bundle_verified\": $bundle_ok/" | \
        sed "s/\"patches_verified\": [a-z]*/\"patches_verified\": $patches_ok/" | \
        sed "s/\"manifest_verified\": [a-z]*/\"manifest_verified\": true/" | \
        sed "s/\"verified_at\": \"[^\"]*\"/\"verified_at\": \"$verified_at\"/")

    atomic_write "$manifest_path" "$content"
    return 0
}

# Update manifest tag_pushed status.
# Usage: manifest_update_tag_pushed <backup_dir> <true|false>
manifest_update_tag_pushed() {
    local backup_dir="$1"
    local pushed="$2"
    local manifest_path="$backup_dir/manifest.json"

    if [[ ! -f "$manifest_path" ]]; then
        return 1
    fi

    local content
    content=$(cat "$manifest_path")
    content=$(echo "$content" | sed "s/\"tag_pushed\": [a-z]*/\"tag_pushed\": $pushed/")

    atomic_write "$manifest_path" "$content"
    return 0
}

# Read a field from manifest.
# Usage: manifest_get <backup_dir> <field>
# Returns: 0 and echoes the value.
manifest_get() {
    local backup_dir="$1"
    local field="$2"
    local manifest_path="$backup_dir/manifest.json"

    if [[ ! -f "$manifest_path" ]]; then
        return 1
    fi

    # Simple grep-based extraction (no jq dependency)
    grep "\"$field\"" "$manifest_path" | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/' | sed 's/.*: *\([0-9]*\).*/\1/'
}
