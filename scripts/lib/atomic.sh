#!/usr/bin/env bash
# Atomic file writing utilities.
# All metadata writes use temp-file + rename to prevent corruption.

# Write content to a file atomically.
# Usage: atomic_write <file_path> <content>
atomic_write() {
    local file="$1"
    local content="$2"
    local tmp="${file}.tmp.$$"

    printf '%s' "$content" > "$tmp"
    sync "$tmp" 2>/dev/null || true
    mv "$tmp" "$file"
}

# Write content to a file atomically from stdin.
# Usage: atomic_write_stdin <file_path>
atomic_write_stdin() {
    local file="$1"
    local tmp="${file}.tmp.$$"

    cat > "$tmp"
    sync "$tmp" 2>/dev/null || true
    mv "$tmp" "$file"
}

# Append a line to a file atomically.
# Usage: atomic_append <file_path> <line>
atomic_append() {
    local file="$1"
    local line="$2"

    # Create file if it doesn't exist
    if [[ ! -f "$file" ]]; then
        touch "$file"
    fi

    # Append is inherently safe for small lines
    printf '%s\n' "$line" >> "$file"
}
