#!/usr/bin/env bash
# Test: regression — dependency-install interruption
# Regression test: when the dependency install phase (within the update provider)
# is interrupted, the next resume should re-run the install phase instead of
# skipping it.

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
LIB_DIR="$PROJECT_ROOT/scripts/lib"

source "$LIB_DIR/logging.sh"
source "$LIB_DIR/exit-codes.sh"
source "$LIB_DIR/atomic.sh"
source "$LIB_DIR/update-state.sh"
source "$LIB_DIR/config.sh"

exit_code=0