# Patch Export/Import with Lockfile Exclusion and Pre-Check

**Feature ID:** `patch-manager`
**Required:** Yes
**Status:** Present
**Date Introduced:** 2026-07-27
**Last Updated:** 2026-07-27
**Related Patches:** (perpetual improvement, no specific patch)

## Purpose

Patch export and import with automatic lockfile exclusion (package-lock.json, yarn.lock, pnpm-lock.yaml) and patch pre-check for already-applied patches.

## User-Visible Behavior

1. `patch_find` (renamed from `patch_list`) skips lockfiles during export and apply — no lockfile patches appear in exported patch bundles.
2. When applying patches, the pre-scan loop uses `git apply --check` to detect patches already incorporated upstream and skips them automatically.
3. Lockfile skip produces a warning message rather than failing the apply.
4. After apply, import verification confirms each module can be imported and key functions are callable.

## Files Modified

- `scripts/lib/patch-manager.sh` — `patch_find` with lockfile exclusion
- `scripts/apply.sh` — pre-scan loop, lockfile skip, already-applied detection, import verification

## Integration Points

- `scripts/lib/patch-manager.sh` — `patch_find` function excludes lockfiles (`package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`) from export results
- `scripts/lib/patch-manager.sh` — `patch_list` kept as deprecated alias for backward compatibility
- `scripts/apply.sh` — pre-scan loop using `git apply --check` to detect already-applied patches before attempting `git am --3way`
- `scripts/apply.sh` — lockfile skip with warning during apply
- `scripts/apply.sh` — import/function verification post-apply

## Dependencies

None

## Restore Strategy

1. Check `scripts/lib/patch-manager.sh` contains `patch_find` function (not just `patch_list`).
2. Check `patch_find` has lockfile exclusion list (package-lock.json, yarn.lock, pnpm-lock.yaml in skip list).
3. Check `scripts/apply.sh` contains pre-scan loop with `git apply --check`.
4. Check `scripts/apply.sh` skips already-applied patches during apply.
5. Verify `git am --3way` is used (not `git am --keep-non-patch`).

## Verification Strategy

```bash
# 1. patch_find function exists
grep -q 'patch_find' scripts/lib/patch-manager.sh

# 2. Lockfile exclusion in patch_find
grep -q 'package-lock.json' scripts/lib/patch-manager.sh
grep -q 'yarn.lock' scripts/lib/patch-manager.sh
grep -q 'pnpm-lock.yaml' scripts/lib/patch-manager.sh

# 3. Pre-scan loop in apply.sh
grep -q 'git apply --check' scripts/apply.sh

# 4. Uses git am --3way (not --keep-non-patch)
grep -q 'git am.*3way' scripts/apply.sh
```

## Migration Notes

No migration needed. These are perpetual improvements that persist across all future updates. `patch_list` is kept as a deprecated alias for backward compatibility.

## Upstream Compatibility

Fully compatible. Uses standard git commands available in all Hermes environments.