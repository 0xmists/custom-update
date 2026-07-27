# Phase-Based Workflow Resume Support

**Feature ID:** `resume-support`
**Required:** Yes
**Status:** Present
**Date Introduced:** 2026-07-27
**Last Updated:** 2026-07-27
**Related Patches:** (core workflow feature)

**Version:** 1  
## Purpose

The custom-update skill uses a phase-based workflow (Backup → Update → Apply → Verify → Publish) with state tracking so that interrupted updates can resume from the last completed phase without re-running earlier steps.

## User-Visible Behavior

1. Each phase of the workflow writes its completion state to `.update-state`.
2. If the workflow is interrupted (user cancellation, system crash, network failure), the next run resumes from the interrupted phase.
3. The menu shows the resume prompt listing the phase with a one-line summary of what will be re-done vs skipped.
4. Backup is never re-created on resume unless the custom state has changed.
5. A phase failure aborts immediately with the exact error.

## Files Modified

- `scripts/lib/update-state.sh` — phase tracking and state persistence
- `scripts/update.sh` — orchestrates phase transitions
- `scripts/backup.sh` — checks for existing backup on resume
- `scripts/menu.sh` — shows resume prompt with phase summary

## Integration Points

- `scripts/lib/update-state.sh` — `get_current_phase()`, `set_phase()`, `clear_state()`
- `scripts/update.sh` — phase transition logic (backup → update → apply → verify → publish)
- `scripts/backup.sh` — reuses latest verified backup if custom state hasn't changed
- `scripts/menu.sh` — displays resume prompt

## Dependencies

- `scripts/lib/update-state.sh` — core dependency for all phase tracking
- `scripts/lib/backup-manager.sh` — used by backup phase to check for existing backups

## Restore Strategy

1. Check `scripts/lib/update-state.sh` exists and contains get/set/clear functions.
2. Check `scripts/update.sh` has phase transition logic.
3. Check `scripts/backup.sh` reuses latest verified backup on resume.
4. Check `scripts/menu.sh` shows resume prompt with phase summary.
5. Verify `.update-state` is created during each phase.

## Verification Strategy

```bash
# 1. update-state.sh exists and has key functions
test -f scripts/lib/update-state.sh
grep -q 'get_current_phase\|set_phase\|clear_state' scripts/lib/update-state.sh

# 2. update.sh has phase transitions
grep -q 'phase\|backup.*update.*apply.*verify.*publish' scripts/update.sh

# 3. backup.sh reuses on resume
grep -q 'resume\|reuse' scripts/backup.sh

# 4. Menu shows resume prompt
grep -q 'resume\|phase.*summary' scripts/menu.sh

# 5. .update-state format check
grep -q '\.update-state\|update_state' scripts/lib/update-state.sh
```

## Migration Notes

No migration needed. This is a core workflow feature.

## Upstream Compatibility

Compatible. Phase tracking uses a simple JSON/key-value file format.