---
name: custom-update
description: "Manage custom Hermes modifications while staying up to date with upstream. Backup, update, apply, restore, and inspect your custom changes."
version: "1.1.0"
author: "Hermes Agent"
license: MIT
platforms: [linux, macos]
metadata:
  hermes:
    tags: [hermes, backup, restore, update, git, custom-modifications]
    related_skills: [hermes-agent]
---

# Hermes Custom

Manage custom Hermes Agent modifications while staying up to date with upstream releases.

## Overview

This skill provides a simple, safe workflow for preserving custom changes across Hermes updates. It creates verified backups, applies patches to updated code, and provides multiple recovery methods.

## Primary Entry Point

```
/custom-update
```

This opens an interactive menu. The user only needs to type the menu number:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Hermes Custom Update v1.0.0
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Repository:  ✓ Healthy
Version:     Hermes Agent v0.16.0 (2026.6.5)
Backup:      20260727-1026-00

Choose an action:

 [1] Update Hermes (Recommended)
    Backup → Update → Apply → Verify → Publish

 [10] Clean Up Backups

 [2] Create Backup

 [3] Restore Previous Version

 [4] Status

 [5] Show Changes (Diff)

 [6] List Backups

 [7] Inspect Backup

 [8] Doctor

 [9] Settings

 [10] Clean Up Backups

 [0] Exit

Enter your choice:
```

The menu orchestrates all underlying commands behind the scenes. After completing an action, it returns to the main menu until the user chooses Exit.

## Commands (Building Blocks)

The following commands remain available for advanced users and automation. They are the building blocks that the interactive menu orchestrates:

|| Command | Description |
||---------|-------------|
|| `hermes custom backup` | Create a verified backup (patches + bundle + tag) |
|| `hermes custom update` | Update Hermes to latest upstream |
|| `hermes custom apply` | Reapply custom patches to updated Hermes |
|| `hermes custom restore` | Restore from a backup (safe, named branch) |
|| `hermes custom list` | List all available backups |
|| `hermes custom status` | Show current state |
|| `hermes custom diff` | Compare current vs upstream |
|| `hermes custom inspect <ID>` | Show detailed backup information |
|| `hermes custom doctor` | Verify environment health |
|| `hermes custom config` | Manage configuration |
|| `hermes custom history` | View operation audit trail |

> **Note:** If `hermes custom` CLI is not registered, the standalone scripts in `~/.hermes/skills/custom-update/scripts/` are used directly. The `doctor` command verifies this and falls back to directory listing if `list.sh` fails. |

## Menu Workflows

### Option 1: Full Update (5-Phase Workflow)
1. **Backup** — Detects if custom state changed; reuses the latest verified
   backup or creates a new one. Pushes to the configured remote.
2. **Update** — Runs `hermes update` (or git-pull). Allows long-running
   dependency installation (managed uv, venv rebuild, Rust/C compilation)
   to complete. Verifies Hermes starts before continuing.
3. **Apply** — Applies custom patches ONLY after the upstream update and
   dependency installation have completed and verified successfully.
   Handles patch conflicts safely. Does NOT apply if the update failed.
4. **Verify** — Verifies the custom build starts and passes health checks.
5. **Publish** — Pushes the updated custom branch/commits to the remote.
   Updates manifest/state files. Runs backup cleanup per retention policy.

If interrupted, the workflow resumes from the last completed phase without
re-running earlier steps (and without creating another backup unless the
custom state has changed). Any phase failure aborts immediately with the
exact error.

The update step uses a configurable timeout (default 30 minutes, configurable
in Settings → Change Update Timeout). For repositories far behind upstream,
the update may take several minutes — this is not treated as an error.

### Option 10: Clean Up Backups
Applies the retention policy: removes old verified backups beyond `max_backups`,
while always protecting the newest verified backup, backups referenced by
interrupted updates, and any unverified or failed backups.

### Option 3: Restore
1. Lists all available backups with verification status
2. User selects a backup by number
3. Restore proceeds automatically using the safest available method

### Option 9: Settings
1. Detect Remotes — auto-detect upstream and fork remotes
2. Change Update Provider — hermes-update or git-pull
3. Toggle Backup Tag Push — on/off
4. Change Backup Location
5. Show Current Configuration
6. Change Update Timeout — 300-7200 seconds (0 for unlimited, default 1800)

## Workflow

```
Primary:  menu → backup → update → apply → verify → publish
Recovery: menu → restore
Read-only: status, diff, inspect, list, history, config, cleanup
```

## Command Lifecycle

```
Primary workflow (phase-based, resumable):
  backup
    ↓
  update
    ↓
  apply
    ↓
  verify
    ↓
  publish

Recovery workflow:
  restore

Read-only commands (no state changes):
  status, diff, inspect, list, history, config, cleanup
```

## Architecture

```
backup.sh → backup-manager.sh → git-utils.sh
                    ↓
            patch-manager.sh
            bundle-manager.sh
            manifest.sh
            verifier.sh
            update-state.sh   (phase tracking for resume)
```

Each command is a thin wrapper. Shared logic lives in library modules under `scripts/lib/`.

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Validation / Doctor failure |
| 3 | Patch application conflict |
| 4 | Backup verification failure |
| 5 | Restore failure |
| 6 | Repository not found |
| 7 | Backup not found |

## Backup Format

Backups are stored in `~/.hermes/custom-backups/` with unique IDs (e.g., `20260726-2130-f31c`).

Each backup contains:
- `patches/` — exported custom commits as `.patch` files
- `backup.bundle` — complete Git bundle
- `manifest.json` — canonical metadata (includes `state_fingerprint`)
- `verification.json` — verification results
- `.update-state` — persistent phase tracking for interrupted-update resume

## Recovery Methods

1. **Git Tag** — fastest, creates `restore/<ID>` branch
2. **Git Bundle** — most complete, works if repo is destroyed
3. **Exported Patches** — most flexible, applies to any base

## Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md) — detailed architecture and implementation guide
- [references/exit-codes.md](references/exit-codes.md) — exit code reference
- [references/backup-format.md](references/backup-format.md) — backup format specification
