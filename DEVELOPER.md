# Development Guide

## Project Overview

The custom-update skill is a standalone Git project (`0xmists/custom-update`) that provides a safe, phase-based workflow for managing custom Hermes Agent modifications across upstream updates.

## Repository Layout

```
scripts/          # All executable scripts
scripts/lib/      # Shared library modules
scripts/lib/update-providers/  # Provider-specific implementations
tests/             # Automated test suite
  unit/            # Unit tests (isolated function tests)
  integration/     # Integration tests (full workflow)
  regression/      # Regression tests (known bug fixes)
.github/workflows/ # CI configuration
```

## Key Files

| File | Purpose |
|------|---------|
| `scripts/lib/hermes-adapter.sh` | Hermes installation abstraction |
| `scripts/lib/config.sh` | Configuration management |
| `scripts/lib/update-state.sh` | Update state persistence |
| `scripts/lib/backup-manager.sh` | Backup lifecycle |
| `scripts/lib/manifest.sh` | Manifest JSON management |
| `scripts/lib/git-utils.sh` | Git helper functions |
| `scripts/lib/logging.sh` | Logging utilities |
| `scripts/lib/exit-codes.sh` | Standard exit codes |

## Running Tests

```bash
# Full test suite
bash tests/run-tests.sh

# Unit tests only
bash tests/run-tests.sh --unit

# Integration tests only
bash tests/run-tests.sh --integration

# Regression tests only
bash tests/run-tests.sh --regression

# Verbose output
bash tests/run-tests.sh --unit --verbose
```

## Code Conventions

1. All scripts use `set -uo pipefail`.
2. All function-local variables are declared with `local`.
3. All variable expansions are quoted.
4. All errors are logged via `log_error`.
5. All exit codes come from `scripts/lib/exit-codes.sh`.
6. Hermes-specific operations go through the `hermes-adapter.sh` functions.
7. No hardcoded paths to the Hermes installation.

## Adding a New Script

1. Source `exit-codes.sh`, `logging.sh`, and any libraries your script needs.
2. Use `hermes_resolve_root`, `hermes_verify_healthy`, etc. instead of hardcoding paths.
3. Add the command to the menu in `scripts/menu.sh`.
4. Write a corresponding unit test in `tests/unit/`.

## Release Process

1. Update the version number in `scripts/lib/hermes-adapter.sh` and `config.yaml`.
2. Update `CHANGELOG.md` with the changes.
3. Update `README.md` if user-facing behavior changed.
4. Run the full test suite: `bash tests/run-tests.sh`.
5. Commit with a version tag: `git tag -a v1.0.0 -m "Release v1.0.0"`.
6. Push the tag: `git push origin --tags`.

## Environment

- **Shell**: Bash 4.2+
- **Platform**: Primarily Linux/Termux, macOS compatible
- **Dependencies**: Git, Bash, standard Unix utilities (grep, sed, awk, find)