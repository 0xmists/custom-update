# Restore --auto-confirm Flag

**Feature ID:** `auto-confirm`
**Required:** Yes
**Status:** Present
**Date Introduced:** 2026-07-27
**Last Updated:** 2026-07-27
**Related Patches:** (perpetual improvement, no specific patch)

**Version:** 1  
## Purpose

Non-interactive restore support via `--auto-confirm` flag, propagated from menu.sh through restore.sh to all subcommands. Fixes the hang-on-pipe issue when restore is invoked non-interactively.

## User-Visible Behavior

1. Running restore from menu never hangs waiting for input.
2. `restore.sh` accepts `--auto-confirm` and skips all interactive prompts.
3. The flag propagates through `_restore_from_tag`, `_restore_from_patches`, and any future restore subcommands.
4. The menu passes `--auto-confirm` automatically when invoking restore.

## Files Modified

- `scripts/restore.sh` — `--auto-confirm` in `_restore_from_tag` and `_restore_from_patches`
- `scripts/menu.sh` — passes `--auto-confirm` to `restore.sh`

## Integration Points

- `scripts/restore.sh:_restore_from_tag()` — accepts `--auto-confirm`, uses it without prompting
- `scripts/restore.sh:_restore_from_patches()` — accepts `--auto-confirm`, uses it without prompting
- `scripts/restore.sh:main()` — passes `--auto-confirm` to subcommands
- `scripts/menu.sh` — passes `--auto-confirm` to `restore.sh` when calling restore action

## Dependencies

None

## Restore Strategy

1. Check `scripts/restore.sh` accepts `--auto-confirm` flag in its argument parsing.
2. Check `_restore_from_tag` and `_restore_from_patches` handle the flag without prompting.
3. Check `scripts/restore.sh:main()` passes `--auto-confirm` to subcommands.
4. Check `scripts/menu.sh` passes `--auto-confirm` to `restore.sh`.

## Verification Strategy

```bash
# 1. restore.sh has --auto-confirm handling
grep -q '\-\-auto-confirm' scripts/restore.sh

# 2. Menu passes --auto-confirm to restore.sh
grep -q '\-\-auto-confirm' scripts/menu.sh

# 3. No interactive prompts when --auto-confirm is set
# (verify that _restore_from_tag and _restore_from_patches
#  check auto_confirm before prompting)
```

## Migration Notes

No migration needed. These are perpetual improvements that persist across all future updates.

## Upstream Compatibility

Fully compatible. Uses standard bash flag parsing.