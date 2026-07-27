# HermesVault Write Detection and Tracking

**Feature ID:** `hermes-vault`
**Required:** Yes
**Status:** Adapted (restored from v0.16.0 for v0.19.0 architecture)
**Date Introduced:** 2026-07-27 (original patches 0001-0004)
**Last Updated:** 2026-07-28 (restored for v0.19.0)
**Related Patches:** 0001, 0002, 0003, 0004

**Version:** 2  
## Purpose

When the Hermes background review agent writes to HermesVault files, the user should see which vault file changed with a specific path. The review agent should automatically update `vault-write-tracker.md` after each vault write. The review prompt should clearly instruct the agent to use `write_file` (not `memory` tool) for vault writes.

## User-Visible Behavior

1. The background review agent has `file` in its tool whitelist, so it CAN write to vault files using `write_file`.
2. Vault writes appear in summaries as `Vault Behavior/observed-patterns.md updated` (specific file path, not just subfolder).
3. Vault subfolder labels (Behavior, Goals, Lessons, Projects, Reflections, Skills, Agents-hub) are recognized and surfaced.
4. The review prompt instructs the agent to update `vault-write-tracker.md` when it writes vault files (prepend entry, keep 20 max).
5. The review prompt clarifies that vault writes use `write_file` (file toolset), not the `memory` tool.
6. Denying the `file` toolset to the review agent produces a message including "file" alongside memory/skill.

## Files Modified

- `agent/background_review.py` — all vault integration changes

## Integration Points

- `background_review.py:837` — `review_toolsets = ["skills", "file"]` so write_file is available
- `background_review.py:430` — `notify_tools = {"memory", "skill_manage", "write_file"}` so vault writes are tracked
- `background_review.py:531-548` — vault write detection in `summarize_background_review_actions()` with subfolder labels and specific file paths
- `background_review.py:851` — `deny_msg_fmt` includes "file" tools
- `background_review.py:872` — user message for review agent includes "file management tools"
- `background_review.py:178-193` — `_MEMORY_REVIEW_PROMPT` includes vault-write-tracker update instructions and write_file vs memory clarification

## Dependencies

None (all changes are additive to `agent/background_review.py`)

## Restore Strategy

6 additive changes to `agent/background_review.py` (nothing replaced or removed):

1. **Line ~837** — Add `"file"` to `review_toolsets` so the background review agent can use `write_file`
2. **Line ~430** — Add `"write_file"` to `notify_tools` so vault write results are tracked in summaries
3. **Lines ~531-548** — After the `label` assignment, add vault write detection: check if `detail["tool"] == "write_file"` and `target` path contains HermesVault or starts with a vault subfolder prefix. Format as `Vault {rel} updated` with the specific vault-relative path.
4. **Line ~851** — Update `deny_msg_fmt` to include "file" alongside memory/skill
5. **Line ~872** — Update user message to the review agent to include "file management tools"
6. **Line ~178-193** — Append to `_MEMORY_REVIEW_PROMPT`: (a) vault-write-tracker update instructions (read tracker, prepend entry, keep 20, use write_file), and (b) write_file vs memory clarification for vault paths

**Key design decision:** All changes are additive. No v0.19.0 code was removed or replaced. The vault detection logic was inserted after the existing label assignment in `summarize_background_review_actions`, before the verbose/non-verbose formatting.

## Verification Strategy

```bash
# 1. review_toolsets includes 'file'
grep -q 'review_toolsets = \["skills", "file"\]' agent/background_review.py

# 2. notify_tools includes 'write_file'
grep -q '"write_file"' agent/background_review.py | grep -q 'notify_tools'

# 3. Vault write detection exists (HermesVault path matching)
grep -q 'hermes.*vault.*write.*detect\|write_file.*HermesVault' agent/background_review.py

# 4. Vault subfolder labels exist
grep -q 'target.startswith("Behavior/")' agent/background_review.py
grep -q 'target.startswith("Goals/")' agent/background_review.py
grep -q 'target.startswith("Lessons/")' agent/background_review.py
grep -q 'target.startswith("Projects/")' agent/background_review.py
grep -q 'target.startswith("Reflections/")' agent/background_review.py

# 5. Vault file summary format shows specific path
grep -q 'Vault.*updated' agent/background_review.py

# 6. _MEMORY_REVIEW_PROMPT contains vault-write-tracker instructions
grep -q 'vault-write-tracker.md' agent/background_review.py

# 7. _MEMORY_REVIEW_PROMPT contains write_file vs memory clarification
grep -q 'write_file.*NOT.*memory\|NOT the memory tool' agent/background_review.py

# 8. deny_msg_fmt includes file
grep -q 'memory/skill/file' agent/background_review.py

# 9. User message includes file management tools
grep -q 'memory.*skill.*and file' agent/background_review.py

# 10. No upstream behavior regressed
grep -q '"Memory" if target == "memory"' agent/background_review.py
grep -q 'is_skill' agent/background_review.py
```

## Migration Notes

Patches 0001-0004 were originally written for v0.16.0 architecture where HermesVault was the primary memory store and `background_review.py` had a different structure (hardcoded tool whitelist, older summarize function). In v0.19.0:

- The review whitelist is dynamically built from toolsets via `get_tool_definitions()` — so adding `"file"` to `review_toolsets` is the v0.19.0 equivalent of adding `file` to a hardcoded whitelist.
- The summarize function was completely rewritten — vault detection was inserted as new logic in the same location (after label assignment, before verbose/non-verbose formatting).
- The review prompt (`_MEMORY_REVIEW_PROMPT`) was rewritten — vault instructions were appended to the existing prompt string.

No code was removed or replaced. All 6 changes are additive.

## Upstream Compatibility

Compatible with v0.19.0. Upstream removed HermesVault awareness from `background_review.py` between v0.16.0 and v0.19.0; these changes add it back in a way that is additive to the new architecture. The `file` toolset already exists in Hermes v0.19.0 (used by other tools) — we are simply granting the background review agent access to it for vault operations.