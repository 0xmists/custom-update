# Doctor Checks

**Feature ID:** `doctor-checks`
**Required:** Yes
**Status:** Present
**Date Introduced:** 2026-07-27
**Last Updated:** 2026-07-27
**Related Patches:** (perpetual improvement, no specific patch)

## Purpose

Environment health verification covering CLI registration, fork sync, stale restore branches, and lockfile-in-patches warnings. Doctor checks are additive — they warn but don't block operations, keeping the skill simple.

## User-Visible Behavior

Running `doctor.sh` (or `hermes custom doctor`) now checks:
1. **CLI registration** — whether `hermes custom <command>` subcommand exists (warns if not, provides script path fallback)
2. **Fork sync** — compares local HEAD vs remote HEAD, warns if fork is behind
3. **Stale restore branches** — lists any existing `restore/<ID>` branches
4. **Lockfile in patches** — warns if any patch files contain lockfile changes (package-lock.json, yarn.lock, pnpm-lock.yaml)
5. **list.sh fallback** — if `hermes custom list` fails, falls back to directory listing of backups

## Files Modified

- `scripts/doctor.sh` — added 4 checks + list.sh fallback

## Integration Points

- `scripts/doctor.sh` — CLI registration check at the top
- `scripts/doctor.sh` — fork sync check (local vs remote HEAD comparison)
- `scripts/doctor.sh` — stale restore branch detection
- `scripts/doctor.sh` — lockfile-in-patches warning
- `scripts/doctor.sh` — list.sh fallback at the end

## Dependencies

- Patch 0005 (execution_state) — none (doctor checks are independent)
- Patch manager improvements (patch_find, lockfile exclusion) — doctor checks warn about lockfiles that should have been excluded

## Restore Strategy

1. Check `scripts/doctor.sh` contains 4+ check functions + list.sh fallback.
2. Verify each check produces a pass/warn/fail output.
3. Verify doctor doesn't block operations (warnings only).
4. Verify the fallback to directory listing if `list.sh` fails.

## Verification Strategy

```bash
# 1. Doctor script exists and is executable
test -x scripts/doctor.sh

# 2. CLI registration check exists
grep -q 'hermes custom\|CLI\|subcommand' scripts/doctor.sh

# 3. Fork sync check exists
grep -q 'fork\|upstream.*HEAD\|remote.*HEAD\|sync' scripts/doctor.sh

# 4. Stale restore branch check exists
grep -q 'restore/' scripts/doctor.sh | grep -q 'branch\|stale'

# 5. Lockfile warning exists
grep -q 'lockfile\|package-lock\|yarn.lock\|pnpm-lock' scripts/doctor.sh

# 6. list.sh fallback exists
grep -q 'list.sh\|fallback' scripts/doctor.sh
```

## Migration Notes

No migration needed. This is a perpetual improvement.

## Upstream Compatibility

Fully compatible. Doctor checks are read-only — they never modify git state or files.