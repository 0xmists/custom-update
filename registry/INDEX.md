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

## Feature Versioning

Each feature has a `version` field (integer) in `features.json`.
When a feature's implementation or behavior changes significantly,
increment the version and update the documentation file.

Do NOT create duplicate feature entries for behavior-preserving changes.

## Verification Evidence

After every restore, `verify_registry.sh` records evidence for each
feature showing exactly what was checked to reach its PASS/FAIL status.

The evidence table is printed as part of the restore report and can be
saved for audit purposes.

## Restore Gate

A restore is considered successful only if:
- Every required feature is verified (PASS, ADAPTED, or PROVIDED_BY_UPSTREAM),
- No required feature is FAILED or MISSING,
- No required feature requires MANUAL_MIGRATION that has not been completed.

If any required feature fails the gate, the restore stops and reports
which features are unresolved. The workflow never reports "Update complete"
while required features remain unresolved.

## Restore Report Format

```
=== Restore Report ===
Feature                    Version  Status    Evidence
execution-state            v2       PASS      all 5 files present with key functions
hermes-vault               v2       ADAPTED   review_toolsets contains file|notify_tools contains write_file|...
patch-manager              v1       PASS      all_files_present
auto-confirm               v1       PASS      all_files_present
stale-branch-cleanup       v1       PASS      all_files_present
doctor-checks              v1       PASS      all_files_present
resume-support             v1       PASS      all_files_present
retention                  v1       PASS      all_files_present
```

## Feature Dependencies

Features can declare dependencies in `features.json`. If a dependency
fails verification, the report clearly identifies the root cause.

Example: `hermes-vault` depends on background_review.py having the
`file` toolset. If the `file` toolset is missing, the hermes-vault
check fails and the report identifies it as a dependency failure.
