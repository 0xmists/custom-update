#!/usr/bin/env bash
# Bundle manager for the custom-update skill.
# Handles creating and verifying Git bundles.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/logging.sh"

# Create a Git bundle of the entire repository.
# Usage: bundle_create <output_path>
# Returns: 0 on success, 1 on failure.
# Echoes: bundle size in bytes.
bundle_create() {
    local output_path="$1"
    local bundle_dir
    bundle_dir=$(dirname "$output_path")
    mkdir -p "$bundle_dir"

    log_info "Creating Git bundle..."
    if ! git bundle create "$output_path" --all 2>/dev/null; then
        log_error "Failed to create Git bundle"
        return 1
    fi

    local size
    size=$(stat -c%s "$output_path" 2>/dev/null || stat -f%z "$output_path" 2>/dev/null || echo 0)
    log_info "Bundle created: $output_path ($size bytes)"
    echo "$size"
    return 0
}

# Verify a Git bundle.
# Usage: bundle_verify <bundle_path>
# Returns: 0 if valid, 1 if invalid.
bundle_verify() {
    local bundle_path="$1"

    if [[ ! -f "$bundle_path" ]]; then
        log_error "Bundle file not found: $bundle_path"
        return 1
    fi

    if ! git bundle verify "$bundle_path" 2>/dev/null; then
        log_error "Bundle verification failed: $bundle_path"
        return 1
    fi

    log_info "Bundle verified: $bundle_path"
    return 0
}

# Get bundle size.
# Usage: bundle_size <bundle_path>
# Returns: 0 and echoes size in bytes.
bundle_size() {
    local bundle_path="$1"
    stat -c%s "$bundle_path" 2>/dev/null || stat -f%z "$bundle_path" 2>/dev/null || echo 0
}
