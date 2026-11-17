#!/usr/bin/env bash
# PostToolUse Agent telemetry — Ticket 4 (the "cost" half of the routing ledger).
#
# Appends one JSON line per completed subagent to .claude/routing-log.jsonl, alongside the
# lines /run-at writes with source:"manual". This closes the gap the ticket assumed was
# permanent ("tokens/cuota por tier NO es auto-capturable — /usage es interactivo"): a
# PostToolUse hook on the Agent tool receives per-subagent usage telemetry directly.
#
# The field that matters most is resolvedModel — "the model the subagent started on, which
# may differ from the requested model" (v2.1.174+). Comparing REQUESTED vs RESOLVED is the
# only way to see the failures the kit is otherwise blind to:
#   - CLAUDE_CODE_SUBAGENT_MODEL set (overrides BOTH the per-invocation model AND the agent's
#     own frontmatter model — one env var makes this whole kit inert, with no error)
#   - an org `availableModels` allowlist, or a --fallback-model kicking in
#   - Ticket 7's silent downgrade, which until now was policy prose with nothing measuring it
#
# When the caller didn't pass a model, the expected tier is read from the kit's own
# agents/<name>.md frontmatter — otherwise the detector would be blind exactly where the kit
# does its routing.
#
# Contract: telemetry MUST NEVER break a session. No `set -e`, every path exits 0, all output
# goes to the log file (never stdout/stderr, which PostToolUse would surface to the model).

set -uo pipefail

payload="$(cat 2>/dev/null || true)"
[ -n "$payload" ] || exit 0

# jq is required to parse nested tool_response safely. Without it, log nothing rather than
# risk a malformed line — a corrupt ledger is worse than a missing one.
command -v jq >/dev/null 2>&1 || exit 0

tool_name="$(printf '%s' "$payload" | jq -r '.tool_name // ""' 2>/dev/null || echo "")"
[ "$tool_name" = "Agent" ] || exit 0

# Namespace-prefixed dispatches ("model-routing-kit:implementer") must resolve to the bare
# name — same reason scope-guard.sh strips it.
agent_raw="$(printf '%s' "$payload" | jq -r '.tool_input.subagent_type // .tool_response.agentType // ""' 2>/dev/null || echo "")"
agent="${agent_raw##*:}"

requested="$(printf '%s' "$payload" | jq -r '.tool_input.model // ""' 2>/dev/null || echo "")"
resolved="$(printf '%s' "$payload" | jq -r '.tool_response.resolvedModel // ""' 2>/dev/null || echo "")"

# No explicit model on the call → the kit agent's frontmatter tier is what SHOULD have run.
if [ -z "$requested" ] && [ -n "$agent" ] && [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  agent_file="${CLAUDE_PLUGIN_ROOT}/agents/${agent}.md"
  if [ -f "$agent_file" ]; then
    requested="$(sed -n 's/^model:[[:space:]]*//p' "$agent_file" 2>/dev/null | head -n1 \
      | sed 's/[[:space:]]*$//')"
  fi
fi

# Mismatch = we know what was asked for, we know what ran, and the resolved name doesn't
# carry the requested alias. Full names ("claude-opus-5") contain their alias ("opus"), so a
# substring test covers alias-vs-fullname without a mapping table. Unknown on either side
# reports "unknown" rather than a false negative.
if [ -n "$requested" ] && [ -n "$resolved" ]; then
  if printf '%s' "$resolved" | grep -qi -- "$requested"; then mismatch=false; else mismatch=true; fi
else
  mismatch=null
fi

log_dir="${CLAUDE_PROJECT_DIR:-$PWD}/.claude"
mkdir -p "$log_dir" 2>/dev/null || exit 0

printf '%s' "$payload" | jq -c \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg agent "$agent" \
  --arg requested "$requested" \
  --argjson mismatch "$mismatch" \
  '{
     ts: $ts,
     source: "agent",
     agent: $agent,
     requested_model: $requested,
     resolved_model: (.tool_response.resolvedModel // ""),
     models_used: (.tool_response.modelsUsed // null),
     model_mismatch: $mismatch,
     status: (.tool_response.status // ""),
     total_tokens: (.tool_response.totalTokens // null),
     input_tokens: (.tool_response.usage.input_tokens // null),
     output_tokens: (.tool_response.usage.output_tokens // null),
     cache_read_tokens: (.tool_response.usage.cache_read_input_tokens // null),
     cache_creation_tokens: (.tool_response.usage.cache_creation_input_tokens // null),
     duration_ms: (.tool_response.totalDurationMs // null),
     tool_use_count: (.tool_response.totalToolUseCount // null),
     description: (.tool_input.description // "")
   }' >> "$log_dir/routing-log.jsonl" 2>/dev/null || true

exit 0
