#!/usr/bin/env bash
# Test: backup creation and reuse
# Integration test verifying the full backup lifecycle.

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
LIB_DIR="$PROJECT_ROOT/scripts/lib"

source "$LIB_DIR/logging.sh"
source "$LIB_DIR/exit-codes.sh"
source "$LIB_DIR/atomic.sh"
source "$LIB_DIR/backup-manager.sh"
source "$LIB_DIR/manifest.sh"
source "$LIB_DIR/config.sh"
source "$LIB_DIR/git-utils.sh"

exit_code=0