# Custom Feature Registry

The Custom Feature Registry is the source of truth for "custom-update". It tracks every custom feature in the Hermes fork, how to verify it, how to restore it, and what its relationship to upstream is.

## Purpose

"custom-update" is feature-aware, not just patch-aware. When restoring a backup, the skill checks every required feature against the registry. If any required feature is missing, the restore fails with a detailed report instead of reporting success.

## Registry Structure

```
registry/
├── INDEX.md                  ← this file
├── features.json             ← machine-readable manifest
├── execution-state.md        ← execution_state + execution_context (patch 0005)
├── hermes-vault.md           ← vault write detection + tracking (patches 0001-0004)
├── patch-manager.md          ← patch_find, precheck, lockfile exclusion (v1.1.0)
├── auto-confirm.md           ← --auto-confirm flag (v1.1.0)
├── stale-branch-cleanup.md   ← stale restore branch detection (v1.1.0)
├── doctor-checks.md          ← doctor CLI check + stale branch + lockfile (v1.1.0)
├── resume-support.md         ← phase-based workflow resume
└── retention.md              ← backup retention policy
```

## Feature Status Definitions

| Status | Meaning |
|--------|---------|
| **Present** | Feature exists in the current Hermes codebase, no action needed |
| **Adapted** | Feature was restored after upstream architecture changes; works in current version |
| **Missing** | Feature is absent — restore must fail |
| **Requires Manual Migration** | Feature exists partially but needs user intervention |

## Workflow Guidelines

Whenever a new custom feature is added to the Hermes fork:

1. Create `registry/<feature-id>.md` with all required fields
2. Add the feature to `features.json`
3. Update the verification strategy so future restores can check it
4. Update the restore strategy so future restores can recover it
5. Update `SKILL.md` to reference the registry

## Restore Verification

After every restore, `scripts/verify_registry.sh` checks every required feature. If any required feature is `Missing`, the restore fails with a restoration report listing the missing feature, reason, affected files, and recommended migration.

The skill never reports "Update complete" while any required feature remains missing.