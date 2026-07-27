# Stale Restore Branch Cleanup

**Feature ID:** `stale-branch-cleanup`
**Required:** Yes
**Status:** Present
**Date Introduced:** 2026-07-27
**Last Updated:** 2026-07-27
**Related Patches:** (perpetual improvement, no specific patch)

**Version:** 1  
## Purpose

When restoring from a backup, detect and handle stale `restore/<ID>` branches in the git repo. If a restore branch already exists (e.g., from a previous interrupted restore), force-recreate it instead of failing with exit code 5.

## User-Visible Behavior

1. Restore creates a `restore/<ID>` branch for safe rollback.
2. If a `restore/<ID>` branch already exists, it is force-recreated instead of failing.
3. This prevents restore failures caused by pre-existing restore branches from previous interrupted operations.

## Files Modified

- `scripts/restore.sh` — stale `restore/<ID>` branch detection with force-recreate

## Integration Points

- `scripts/restore.sh` — main restore logic checks for existing `restore/<ID>` branch before creating a new one
- If the branch exists, it is force-recreated (`git branch -D` + `git branch`)

## Dependencies

None

## Restore Strategy

1. Check `scripts/restore.sh` contains stale branch detection logic (checking for existing `restore/<ID>` branches).
2. Check it force-recreates rather than failing.
3. Verify the detection happens before the restore branch is created.

## Verification Strategy

```bash
# 1. Stale branch detection exists
grep -q 'restore/' scripts/restore.sh | grep -q 'branch\|exist'

# 2. Force recreate behavior
grep -q 'force\|-D\|recreate' scripts/restore.sh
```

## Migration Notes

No migration needed. This is a perpetual improvement.

## Upstream Compatibility

Fully compatible. Uses standard git branch operations.