# Hermes Custom — Architecture

## Overview

The `custom-update` skill provides a safe, verified workflow for managing custom
Hermes Agent modifications across upstream updates. It uses Git patches, bundles,
and tags to create immutable backups with multiple recovery paths.

## Design Principles

1. **Never lose custom work** — backups are verified before reporting success
2. **Manifest as source of truth** — `manifest.json` is the canonical record
3. **Atomic writes** — all metadata uses temp-file + rename
4. **Modular commands** — each command is a thin wrapper over shared libraries
5. **Predictable exit codes** — documented codes for automation
6. **Safe recovery** — never leaves user in detached HEAD

## Directory Structure

```
~/.hermes/skills/custom-update/
├── SKILL.md                          # Skill documentation
├── ARCHITECTURE.md                   # This file
├── config.yaml                       # Default configuration template
├── scripts/
    ├── menu.sh                     # Interactive menu (primary entry point)
    ├── doctor.sh                   # Environment verification
    ├── backup.sh                   # Backup orchestration
    ├── update.sh                     # Update orchestration
    ├── apply.sh                      # Patch application
    ├── restore.sh                    # Recovery from backup
    ├── list.sh                       # List backups (read from manifest)
    ├── status.sh                     # Show current state
    ├── diff.sh                       # Compare vs upstream
    ├── inspect.sh                    # Detailed backup info
    ├── history.sh                    # Operation audit trail
    ├── config.sh                     # Configuration management
    └── lib/
        ├── exit-codes.sh             # Documented exit codes
        ├── logging.sh                # Structured logging
        ├── atomic.sh                 # Atomic file writes
        ├── git-utils.sh              # Shared Git operations
        ├── repo-locator.sh           # Hermes repo discovery
        ├── config.sh                 # Configuration management
        ├── history.sh                # Operation history logger
        ├── remote-detector.sh        # Auto-detect upstream/fork remotes
        ├── patch-manager.sh          # Patch export/verify
        ├── bundle-manager.sh         # Git bundle create/verify
        ├── manifest.sh               # Manifest generation/parsing
        ├── verifier.sh               # Backup integrity verification
        └── update-state.sh             # Persistent phase tracking for resume
        └── update-providers/
            ├── hermes-update.sh      # Provider: hermes update
            └── git-pull.sh           # Provider: git pull
```

## Command Architecture

Each command script follows the same pattern:

```
1. Source exit-codes.sh, logging.sh
2. Source lib modules (git-utils, repo-locator, config, etc.)
3. Define command-specific helper functions
4. Define main function
5. Call main with "$@"
```

### Command → Library Dependencies

| Command   | Libraries Used                                           |
|-----------|----------------------------------------------------------|
| menu      | exit-codes, logging, git-utils, repo-locator, config, history, remote-detector, manifest |
| doctor    | exit-codes, logging, git-utils, repo-locator, config, remote-detector |
| backup    | exit-codes, logging, git-utils, repo-locator, config, remote-detector, atomic, history, patch-manager, bundle-manager, manifest, verifier, update-state |
| update    | exit-codes, logging, git-utils, repo-locator, config, history, update-state, backup-manager, update-providers |
| apply     | exit-codes, logging, git-utils, repo-locator, config, history, patch-manager |
| restore   | exit-codes, logging, git-utils, repo-locator, config, history, manifest |
| list      | exit-codes, logging, config, manifest |
| status    | exit-codes, logging, git-utils, repo-locator, config, history |
| diff      | exit-codes, logging, git-utils, repo-locator, config |
| inspect   | exit-codes, logging, git-utils, repo-locator, config, history, manifest |
| history   | exit-codes, logging, config, history |
| config    | exit-codes, logging, git-utils, repo-locator, config, remote-detector |

## Manifest as Source of Truth

The `manifest.json` file is the canonical record for each backup. Read-only
commands (`list`, `inspect`, `status`, `history`) read primarily from the manifest
instead of independently scanning Git state.

### Manifest Schema

```json
{
  "skill_version": "1.0.0",
  "manifest_version": "1.0",
  "backup_id": "20260726-2130-f31c",
  "created_at": "2026-07-26T21:30:00Z",
  "hermes_version": "0.16.0",
  "current_commit": "542e847f5...",
  "current_commit_short": "542e847f5",
  "state_fingerprint": "542e847f5...|abc123,def456|0.16.0",
  "upstream_commit": "6179da549...",
  "upstream_branch": "main",
  "upstream_remote": "origin",
  "fork_remote": "fork",
  "base_commit": "abc123...",
  "patch_count": 6,
  "patch_shas": ["sha1", "sha2", ...],
  "patch_files": ["0001-...", "0002-...", ...],
  "files_modified": ["agent/agent_init.py", ...],
  "tag": "backup/20260726-2130-f31c",
  "tag_pushed": true,
  "bundle_size": 12345678,
  "verification": {
    "status": "verified",
    "bundle_verified": true,
    "patches_verified": true,
    "verified_at": "2026-07-26T21:30:01Z"
  }
}
```

## Phase-Based Workflow

The update workflow follows a strict 5-phase sequence with persistent state
tracking so interrupted runs resume from the last completed phase:

1. **Backup** — Detect if custom state changed; reuse latest verified backup
   or create a new one. Push to remote.
2. **Update** — Run `hermes update` (or git-pull). Allow long-running dependency
   installation (managed uv, venv rebuild, Rust/C compilation) to complete.
   Verify Hermes starts before continuing.
3. **Apply** — Apply custom patches ONLY after Phase 2 succeeds. Handle
   conflicts safely. Never apply if the update failed.
4. **Verify** — Verify the custom build starts and passes health checks.
5. **Publish** — Push updated branch/commits, update manifest/state, run
   backup cleanup per retention policy.

State file (`.update-state` in the backup dir) records each phase's status.
On failure, the phase is marked pending and the workflow aborts immediately
with the exact error. Resume re-runs from the first incomplete phase.

### Phase Ordering Guarantees

- Custom patches are NEVER applied until the upstream update and dependency
  installation have completed and Hermes has been verified to start.
- The publish phase NEVER runs unless verification passed.
- A new backup is NEVER created on resume unless the custom state has changed
  (detected via `state_fingerprint` in the manifest).

## Atomic Writes

All metadata files use the temp-file + rename pattern to prevent corruption:

```bash
atomic_write() {
    local file="$1"
    local content="$2"
    local tmp="${file}.tmp.$$"
    printf '%s' "$content" > "$tmp"
    sync "$tmp"
    mv "$tmp" "$file"
}
```

Files using atomic writes:
- `manifest.json`
- `verification.json`
- `config.yaml`
- `history.log`
- `.update-state`

## Exit Codes

| Code | Meaning                          |
|------|----------------------------------|
| 0    | Success                          |
| 1    | General error                    |
| 2    | Validation / Doctor failure      |
| 3    | Patch application conflict       |
| 4    | Backup verification failure      |
| 5    | Restore failure                  |
| 6    | Repository not found             |
| 7    | Backup not found                 |

## Recovery Strategy

The `restore` command detects available recovery methods and recommends the
safest option:

1. **Git Tag** (highest priority) — fastest, creates `restore/<ID>` branch
2. **Git Bundle** — most complete, works if repo is destroyed
3. **Exported Patches** — most flexible, applies to any base

The restore command always creates a named branch (`restore/<ID>`) and never
leaves the user in a detached HEAD state.

## Update Provider Abstraction

The update system supports pluggable providers:

```
update.sh → update_provider.sh (selected via config)
```

Built-in providers:
- `hermes-update` — uses `hermes update` command
- `git-pull` — uses `git pull <upstream> main`

Custom providers can be added to `scripts/lib/update-providers/`.

## Testing

Run the doctor command to verify the environment:

```bash
hermes custom doctor
```

Test the full workflow:

```bash
hermes custom doctor
hermes custom backup
hermes custom status
hermes custom list
hermes custom inspect <BACKUP_ID>
```
