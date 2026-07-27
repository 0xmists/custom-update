# Execution State Management

**Feature ID:** `execution-state`
**Required:** Yes
**Status:** Present
**Date Introduced:** 2026-07-27
**Last Updated:** 2026-07-27
**Related Patches:** 0005

**Version:** 2  
## Purpose

Atomic JSON-based execution marker persistence and execution context propagation across the Hermes gateway pipeline. Enables the Hermes adapter layer (hermes_resolve_root, hermes_execute_update, hermes_verify_healthy) to coordinate background watcher tasks.

## User-Visible Behavior

1. Execution markers are created atomically (write + rename) preventing partial-state corruption during watcher lifecycle tracking.
2. The background review agent's `write_file` calls are tracked with specific output paths — the agent knows when a watcher's file write completed.
3. The Hermes adapter layer resolves the Hermes root directory from any execution context without requiring environment variables or config file parsing.
4. Execution context propagates from webhook → gateway → agent so background tasks carry their origin context through the entire pipeline.

## Files Modified

- `agent/execution_state.py` — atomic JSON marker persistence (create/load/update/remove)
- `agent/tool_executor.py` — calls `_publish_execution_completion` after `write_file`
- `gateway/platforms/base.py` — `MessageEvent.execution_context` field
- `gateway/platforms/webhook.py` — reads `execution_context` from webhook payload
- `gateway/run.py` — sets `agent._execution_context` from `MessageEvent`

## Integration Points

- `agent/execution_state.py` — atomic JSON marker persistence (create/load/update/remove)
- `agent/tool_executor.py` — `_publish_execution_completion` after `write_file` in both concurrent and sequential paths
- `gateway/platforms/base.py` — `MessageEvent.execution_context` field declaration
- `gateway/platforms/webhook.py` — reads `execution_context` from webhook payload, attaches to `MessageEvent`
- `gateway/run.py` — sets `agent._execution_context` from `MessageEvent` before `agent.run_conversation()`

## Dependencies

None

## Restore Strategy

1. Check all 5 files exist at their expected paths.
2. Verify `agent/execution_state.py` contains `create_execution_marker`, `load_execution_marker`, `update_execution_marker`, `remove_execution_marker`.
3. Verify `agent/tool_executor.py` has `from agent.execution_state import` and `_publish_execution_completion`.
4. Verify `gateway/platforms/base.py` has `execution_context` field on `MessageEvent`.
5. Verify `gateway/platforms/webhook.py` populates `execution_context`.
6. Verify `gateway/run.py` sets `agent._execution_context`.
7. Diff against backup commit `542e847f5` for exact content match.

## Verification Strategy

```bash
# 1. execution_state.py exists and contains key functions
grep -q 'create_execution_marker' agent/execution_state.py
grep -q 'load_execution_marker' agent/execution_state.py
grep -q 'update_execution_marker' agent/execution_state.py
grep -q 'remove_execution_marker' agent/execution_state.py

# 2. tool_executor.py imports and calls execution state
grep -q 'from agent.execution_state import' agent/tool_executor.py
grep -q '_publish_execution_completion' agent/tool_executor.py

# 3. base.py has execution_context field
grep -q 'execution_context' gateway/platforms/base.py

# 4. webhook.py populates execution_context
grep -q 'execution_context' gateway/platforms/webhook.py

# 5. run.py sets _execution_context
grep -q '_execution_context' gateway/run.py
```

## Migration Notes

No migration needed. Patch 0005 has been present since v0.16.0 and is fully compatible with v0.19.0. The content in HEAD (`1a61b2480`) is identical to the backup commit (`542e847f5`).

## Upstream Compatibility

Compatible with v0.19.0. Hermes v0.19.0's architecture supports the same atomic JSON approach for execution markers. No upstream conflicts.