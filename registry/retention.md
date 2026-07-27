# Backup Retention and Cleanup Policy

**Feature ID:** `retention`
**Required:** Yes
**Status:** Present
**Date Introduced:** 2026-07-27
**Last Updated:** 2026-07-27
**Related Patches:** (core workflow feature)

**Version:** 1  
## Purpose

Manages backup cleanup according to a retention policy. Removes old verified backups beyond `max_backups` while protecting the newest verified backup, backups referenced by interrupted updates, and any unverified or failed backups.

## User-Visible Behavior

1. Running "Clean Up Backups" (menu option 10) removes old backups beyond the retention limit.
2. The newest verified backup is always protected.
3. Backups referenced by interrupted updates are preserved.
4. Unverified or failed backups are preserved (they may contain needed state).
5. `max_backups` is configurable in Settings.

## Files Modified

- `scripts/lib/backup-manager.sh` — retention policy logic
- `scripts/menu.sh` — clean up option
- `scripts/config.sh` — `max_backups` setting

## Integration Points

- `scripts/lib/backup-manager.sh` — `cleanup_old_backups()` function
- `scripts/lib/backup-manager.sh` — `get_retention_policy()` function
- `scripts/config.sh` — `max_backups` configuration variable
- `scripts/menu.sh` — option 10 triggers cleanup

## Dependencies

- Backup verification (each backup must be verified before cleanup considers it "verified")
- Update state tracking (backups referenced by interrupted updates must be preserved)

## Restore Strategy

1. Check `scripts/lib/backup-manager.sh` contains retention/cleanup logic.
2. Check `scripts/config.sh` has `max_backups` setting.
3. Check cleanup protects newest verified backup.
4. Check cleanup preserves unverified/failed backups.

## Verification Strategy

```bash
# 1. Backup manager has cleanup function
grep -q 'cleanup\|retention\|max_backups' scripts/lib/backup-manager.sh

# 2. Config has max_backups
grep -q 'max_backups' scripts/config.sh

# 3. Menu has clean up option
grep -q 'clean\|cleanup\|10' scripts/menu.sh | grep -i backup
```

## Migration Notes

No migration needed. This is a core workflow feature.

## Upstream Compatibility

Compatible. Retention policy is independent of Hermes version.