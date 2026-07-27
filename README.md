# custom-update — Hermes Agent Skill

> Manage custom Hermes Agent modifications across upstream updates with a phase-based workflow, verified backups, and resume support.

[![CI Status](https://img.shields.io/github/actions/workflow/status/0xmists/custom-update/ci.yml)](https://github.com/0xmists/custom-update/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Architecture](#architecture)
- [Workflow](#workflow)
- [State Machine](#state-machine)
- [Backup Reuse](#backup-reuse)
- [Resume Logic](#resume-logic)
- [Retention Policy](#retention-policy)
- [Recovery Guide](#recovery-guide)
- [Troubleshooting](#troubleshooting)
- [Developer Guide](#developer-guide)
- [Contributing](#contributing)

---

## Installation

### Prerequisites

- Hermes Agent installed and accessible via `hermes` command or `run_agent.py`
- Git 2.x+
- Bash 4.2+
- SSH key configured for GitHub (to push tags and branches)

### Quick Install

```bash
# The custom-update skill is located in the Hermes skills directory.
# Ensure it is symlinked or copied into your Hermes skills path:

cp -r /path/to/custom-update ~/.hermes/skills/custom-update
```

### Verification

```bash
hermes custom status
```

You should see the current Hermes version, remote configuration, and backup status.

---

## Quick Start

### 1. Check Status

```bash
hermes custom status
```

Shows the current Hermes version, upstream commit, custom patches applied, and latest backup.

### 2. Create a Backup

```bash
hermes custom backup create
```

Creates a verified backup of the current custom state and tags it in Git.

### 3. Run a Full Update

```bash
hermes custom update
```

This runs the 5-phase workflow:

1. **Backup** — Creates or reuses a verified backup.
2. **Update** — Updates Hermes via the configured provider.
3. **Apply** — Reapplies custom patches after upstream update.
4. **Verify** — Runs health checks to confirm the build works.
5. **Publish** — Pushes updated custom branch and tags to the fork.

### 4. Restore from a Backup

```bash
hermes custom restore [BACKUP_ID]
```

Restores the Hermes installation from a specified backup using the safest available method (Git tag, bundle, or patches).

---

## Configuration

Configuration is stored in `~/.hermes/custom-backups/config.yaml` by default.

### Configuration Keys

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `remotes.upstream` | string | auto-detected | Name of the upstream Git remote |
| `remotes.fork` | string | auto-detected | Name of the fork Git remote |
| `update_provider` | string | `hermes-update` | Update method: `hermes-update`, `git-pull`, or `custom` |
| `backup_dir` | path | `~/.hermes/custom-backups` | Directory for backup storage |
| `backup_tag_prefix` | string | `backup/` | Prefix for Git backup tags |
| `max_backups` | integer | `0` | Maximum backups to keep (`0` = unlimited) |
| `auto_cleanup` | boolean | `true` | Auto-remove old verified backups after update |
| `enable_rerere` | boolean | `true` | Enable `git rerere` for merge conflict recording |
| `enable_stash` | boolean | `true` | Auto-stash uncommitted changes before operations |
| `confirm_destructive` | boolean | `true` | Require confirmation for destructive operations |
| `update_timeout` | integer | `1800` | Timeout for update operations in seconds |

### Setting Configuration

```bash
# Show current configuration
hermes custom config show

# Auto-detect remotes
hermes custom config detect-remotes

# Set a specific value
hermes custom config set max_backups 10
hermes custom config set update_provider git-pull
```

### Environment Variables

| Variable | Overrides |
|----------|-----------|
| `HERMES_ROOT` | Hermes installation root directory |
| `CUSTOM_CONFIG_DIR` | Backup directory path |
| `CUSTOM_CONFIG_FILE` | Path to config.yaml |
| `CUSTOM_LOG_LEVEL` | Log level (DEBUG, INFO, WARN, ERROR) |

---

## Architecture

```
custom-update/
├── scripts/
│   ├── update.sh            # Main update workflow orchestrator
│   ├── backup.sh            # Backup create / cleanup
│   ├── apply.sh             # Apply custom patches
│   ├── restore.sh           # Restore from backup
│   ├── verify.sh            # Standalone verification
│   ├── status.sh            # Show current state
│   ├── doctor.sh            # Environment health check
│   ├── config.sh            # Manage configuration
│   ├── diff.sh              # Compare current vs upstream
│   ├── inspect.sh           # Inspect a specific backup
│   ├── list.sh              # List all backups
│   ├── history.sh           # View operation history
│   ├── menu.sh              # Interactive menu
│   └── lib/
│       ├── hermes-adapter.sh        # Hermes installation abstraction layer
│       ├── config.sh                # Configuration loading/saving
│       ├── logging.sh               # Logging utilities
│       ├── exit-codes.sh            # Standard exit codes
│       ├── atomic.sh                # Atomic file writes
│       ├── git-utils.sh             # Git helper functions
│       ├── repo-locator.sh          # Find and validate Hermes repo
│       ├── remote-detector.sh       # Auto-detect upstream/fork remotes
│       ├── backup-manager.sh        # Backup lifecycle management
│       ├── bundle-manager.sh        # Git bundle creation/verification
│       ├── manifest.sh              # Backup manifest JSON management
│       ├── verifier.sh              # Backup integrity verification
│       ├── patch-manager.sh         # Export and apply patches
│       ├── history.sh               # Operation history logging
│       ├── update-state.sh          # Interrupted update state tracking
│       └── update-providers/
│           ├── hermes-update.sh     # Provider: `hermes update`
│           └── git-pull.sh          # Provider: `git pull`
├── tests/
│   ├── run-tests.sh               # Test runner
│   ├── unit/                      # Unit tests
│   ├── integration/               # Integration tests
│   └── regression/                # Regression tests
├── .github/workflows/ci.yml       # GitHub Actions CI
├── ARCHITECTURE.md                # Detailed architecture guide
├── SKILL.md                       # Skill documentation
├── config.yaml                    # Default configuration
├── .gitignore
└── README.md                      # This file
```

### Key Design Decisions

1. **Hermes Adapter Layer** — All Hermes-specific commands (`hermes update`, `hermes version`) are isolated in `scripts/lib/hermes-adapter.sh`. This means future Hermes internal changes only require updating the adapter, not every script.

2. **Phase-Based Workflow** — The update workflow is broken into 5 phases with persisted state. If any phase fails, the workflow can be resumed from the last incomplete phase without re-running earlier steps.

3. **No Backup Reuse on Failed Updates** — When a previous update was interrupted, backup reuse is disabled to prevent applying stale patches on top of an inconsistent state.

4. **Verify Before Apply** — Custom patches are never applied until the upstream update has completed AND Hermes is confirmed to be healthy. This prevents a broken upstream from corrupting customizations.

---

## Workflow

### Full Update Workflow

```
┌─────────────┐
│  Start       │
└──────┬──────┘
       ▼
┌─────────────┐     ┌──────────────┐
│  Phase 1     │────▶│  Backup      │
│  Backup      │     │  Create or   │
│              │     │  Reuse       │
└─────────────┘     └──────────────┘
                       │
                       ▼
              ┌──────────────┐     ┌──────────────┐
              │  Phase 2     │────▶│  Update      │
              │  Update      │     │  hermes update│
              │              │     │  or git pull  │
              └──────────────┘     └──────────────┘
                                    │
                                    ▼
              ┌──────────────┐     ┌──────────────┐
              │  Phase 3     │────▶│  Apply       │
              │  Apply       │     │  Reapply     │
              │              │     │  custom patches│
              └──────────────┘     └──────────────┘
                                    │
                                    ▼
              ┌──────────────┐     ┌──────────────┐
              │  Phase 4     │────▶│  Verify      │
              │  Verify      │     │  hermes version│
              │              │     │  doctor checks │
              └──────────────┘     └──────────────┘
                                    │
                                    ▼
              ┌──────────────┐     ┌──────────────┐
              │  Phase 5     │────▶│  Publish     │
              │  Publish     │     │  git push     │
              │              │     │  + cleanup    │
              └──────────────┘     └──────────────┘
```

---

## State Machine

The update workflow uses a persistent state file (`.update-state` in the backup directory) to track progress across interruptions.

### States

```
                    ┌──────────────┐
                    │   pending    │
                    └──────┬───────┘
                           │
                    ┌──────▼───────┐
                    │ in_progress  │
                    └──────┬───────┘
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
        ┌──────────┐ ┌──────────┐ ┌──────────┐
        │   done   │ │ pending  │ │interrupted│
        └────┬─────┘ └────┬─────┘ └────┬─────┘
             │            │             │
             │     ┌──────▼───────┐     │
             │     │  (resume from│     │
             │     │   this phase)│     │
             │     └──────────────┘     │
             ▼                           ▼
        (skip if done)         (re-enter on resume)
```

### State Fields

| Field | Values | Description |
|-------|--------|-------------|
| `STATE_BACKUP_PHASE` | `pending`, `in_progress`, `done` | Backup phase status |
| `STATE_UPDATE_PHASE` | `pending`, `in_progress`, `done` | Update phase status |
| `STATE_APPLY_PHASE` | `pending`, `in_progress`, `done` | Apply phase status |
| `STATE_VERIFY_PHASE` | `pending`, `in_progress`, `done` | Verify phase status |
| `STATE_PUBLISH_PHASE` | `pending`, `in_progress`, `done` | Publish phase status |
| `STATE_BACKUP_ID` | string | ID of the backup created for this update |
| `STATE_BACKUP_REUSED` | `true`, `false` | Whether an existing backup was reused |
| `STATE_INTERRUPTED` | `true`, `false` | Whether the update was interrupted |

---

## Backup Reuse

### When Is a Backup Reused?

A backup is reused when ALL of the following conditions are true:

1. A previous verified backup exists.
2. The current custom state (commits, version) matches the backup's recorded state fingerprint.
3. The update phase has NOT already completed (no prior successful update with custom patches applied).
4. The update is not an interrupted resume of a previous failed update.

### Reuse Detection

The `state_fingerprint` field in the manifest records a hash of:

- The current commit hash.
- All custom commit SHAs since the last upstream merge-base.
- The Hermes version string.

If the fingerprint matches, the backup is considered safe to reuse.

### When Is Reuse Disabled?

Backup reuse is automatically disabled when:

- An interrupted update exists (the state file has `interrupted=true`).
- The update phase has already completed (custom patches are already applied for this update).
- No verified backup with a matching fingerprint exists.

---

## Resume Logic

### How Resume Works

When an update is interrupted (e.g., network failure, disk full, process killed), the state file persists which phases completed and which did not. The next time `hermes custom update` is run:

1. The state file is loaded.
2. The workflow identifies the first incomplete phase.
3. It skips all completed phases and resumes from the first incomplete one.
4. Backup creation is skipped if a backup already exists for this update.

### Example Recovery

```bash
# Scenario: Update failed at Phase 3 (Apply)
# State: backup=done, update=done, apply=pending, verify=pending, publish=pending

# Simply run the update again:
hermes custom update

# The workflow will:
# - Skip backup (already done)
# - Skip update (already done)
# - Resume at apply (first pending phase)
# - Continue through verify and publish
```

---

## Retention Policy

### Default Behavior

After a successful update, the cleanup command removes old verified backups that exceed `max_backups`:

- **Protected**: The newest verified backup is never removed.
- **Protected**: Backups referenced by an interrupted update are never removed.
- **Protected**: Unverified and failed backups are never removed (they are candidates only if explicitly pruned via `--dry-run`).
- **Not Protected**: Old verified backups beyond the limit are candidates for removal.

### Configuration

```yaml
max_backups: 10  # Keep the 10 most recent verified backups
auto_cleanup: true  # Run cleanup automatically after successful updates
```

### Manual Cleanup

```bash
# Dry run — show what would be removed
hermes custom backup cleanup --dry-run

# Actual cleanup
hermes custom backup cleanup
```

---

## Recovery Guide

### Recovering from a Failed Update

1. **Check the state**. Run `hermes custom status` to see if an interrupted update exists.
2. **Review the error**. Check the output of the failed command to understand what went wrong.
3. **Fix the issue** (e.g., network, disk space, patch conflict).
4. **Resume**. Run `hermes custom update` again. It will resume from the failed phase.

### Recovering from a Corrupted Backup

```bash
# 1. Find the latest good backup
hermes custom list

# 2. Restore to a specific backup
hermes custom restore <BACKUP_ID>
```

### Recovering When the Backup Directory is Lost

If `~/.hermes/custom-backups/` is lost but Git tags are intact:

1. Fetch tags from the fork: `git fetch fork`
2. List available backup tags: `git tag -l 'backup/*'`
3. Restore from a tag: create a branch from the tag and checkout.

---

## Troubleshooting

### Hermes repository not found

**Symptom**: `locate_hermes_repo` fails with `EXIT_REPO_NOT_FOUND`.

**Causes**:
- Hermes is not installed in any of the searched locations.
- The current directory is not inside a Hermes repository.
- `HERMES_ROOT` is set but points to a non-existent directory.

**Fix**:
```bash
# Explicitly set the Hermes root
export HERMES_ROOT=/path/to/hermes/installation

# Or run the command from inside the Hermes repo
cd /path/to/hermes
hermes custom update
```

### Backup verification failed

**Symptom**: `verify_backup` returns a non-zero exit code.

**Causes**:
- The bundle file is corrupt or missing.
- Patches fail `git apply --check`.
- The manifest is missing required fields.

**Fix**:
```bash
# Create a fresh backup (the failed backup can be ignored)
hermes custom backup create
```

### Update fails at Phase 2 (Update)

**Symptom**: `hermes update` or `git pull` fails.

**Causes**:
- Network connectivity issues.
- Git credentials expired.
- Upstream has rebased/force-pushed.

**Fix**:
```bash
# Check network
git fetch upstream

# If upstream has force-pushed, you may need to rebase
git rebase upstream/main
```

### Interrupted update blocks new updates

**Symptom**: Running `hermes custom update` says "Resuming interrupted update" when you didn't intend to resume.

**Fix**:
```bash
# Check the state file
cat ~/.hermes/custom-backups/.update-state

# If the state is stale, manually remove it
rm ~/.hermes/custom-backups/.update-state
```

---

## Developer Guide

### Adding a New Script

1. Create the script in `scripts/` with a descriptive name.
2. Source the required libraries at the top:
   ```bash
   source "$LIB_DIR/exit-codes.sh"
   source "$LIB_DIR/logging.sh"
   source "$LIB_DIR/git-utils.sh"
   source "$LIB_DIR/hermes-adapter.sh"
   source "$LIB_DIR/config.sh"
   ```
3. Use `hermes_resolve_root`, `hermes_verify_healthy`, and other adapter functions instead of hardcoding Hermes paths.
4. Add the new command to `scripts/menu.sh`.

### Modifying the Hermes Adapter

The Hermes adapter is the primary abstraction point for Hermes internals. Any change to how Hermes is invoked, versioned, or verified should go through the adapter layer.

### Adding a New Update Provider

1. Create `scripts/lib/update-providers/<name>.sh`.
2. Implement `provider_update()` and `provider_verify_update()`.
3. Add the provider name to the `case` statement in `hermes_execute_update()` in `hermes-adapter.sh`.
4. Add the provider to the configuration options in `scripts/lib/config.sh`.

### Testing

```bash
# Run all tests
bash tests/run-tests.sh

# Run only unit tests
bash tests/run-tests.sh --unit

# Run only regression tests
bash tests/run-tests.sh --regression

# Verbose output
bash tests/run-tests.sh --unit --verbose
```

---

## Contributing

### How to Contribute

1. **Fork** the repository on GitHub.
2. **Create a branch** for your changes: `git checkout -b feature/your-feature`.
3. **Write tests** for any new functionality.
4. **Run the full test suite**: `bash tests/run-tests.sh`.
5. **Commit** with a descriptive message.
6. **Push** and open a **Pull Request**.

### Commit Message Convention

```
type: description

Detailed description of what changed and why.

Closes #XXX  (if applicable)
```

Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`

### Code Style

- Use `set -uo pipefail` in all scripts.
- Use `local` for all function-local variables.
- Quote all variable expansions.
- Log errors via `log_error`, info via `log_info`, warnings via `log_warn`.
- Return appropriate exit codes from `scripts/lib/exit-codes.sh`.
- Use the Hermes adapter functions instead of calling Hermes directly.

### PR Checklist

- [ ] All existing tests pass.
- [ ] New tests added for new functionality.
- [ ] ShellCheck passes on all scripts.
- [ ] `bash -n` passes on all scripts.
- [ ] Documentation updated if behavior changes.
- [ ] CHANGELOG updated.

---

## License

MIT License — see [LICENSE](LICENSE) file for details.