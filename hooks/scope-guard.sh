#!/usr/bin/env bash
# PreToolUse scope-guard — feasibility probe for the agent-routing-kit.
# Reads a Claude Code PreToolUse hook payload on stdin and decides allow/deny.
#
# Policy: if the ACTIVE subagent is a UI-only agent (visual-polish / text-and-copy-editor)
# and the tool would touch a RISKY path (adapter|store|schema|persistence|migration|fixture|api),
# block it and tell the agent to escalate. Otherwise allow.
#
# Real hook contract: exit 0 = allow; emit JSON with permissionDecision "deny" to block.
# We use the JSON form so the reason reaches the model.

set -euo pipefail
payload="$(cat)"

# Extract fields with jq (fall back to grep if jq missing).
if command -v jq >/dev/null 2>&1; then
  agent_type="$(printf '%s' "$payload" | jq -r '.agent_type // "main"')"
  tool_name="$(printf '%s' "$payload" | jq -r '.tool_name // ""')"
  # file_path for Edit/Write; command for Bash
  file_path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // ""')"
  command_str="$(printf '%s' "$payload" | jq -r '.tool_input.command // ""')"
else
  agent_type="$(printf '%s' "$payload" | grep -o '"agent_type"[^,]*' | sed 's/.*: *"//; s/".*//' || echo main)"
  tool_name="$(printf '%s' "$payload" | grep -o '"tool_name"[^,]*' | sed 's/.*: *"//; s/".*//' || echo)"
  file_path="$(printf '%s' "$payload" | grep -o '"file_path"[^,]*' | sed 's/.*: *"//; s/".*//' || echo)"
  command_str="$(printf '%s' "$payload" | grep -o '"command"[^}]*' | sed 's/.*: *"//; s/".*//' || echo)"
fi

# Which agents are UI-only (not allowed to touch data/logic)?
case "$agent_type" in
  visual-polish|text-and-copy-editor) ui_only=1 ;;
  *) ui_only=0 ;;
esac

# Risky path pattern.
RISKY='adapter|persistence|store|schema|migration|fixture|/api/|\.sql'

target="$file_path $command_str"

if [ "$ui_only" -eq 1 ] && printf '%s' "$target" | grep -Eiq "$RISKY"; then
  reason="scope-guard: '$agent_type' is UI-only but tried to touch a data/logic path ($target). Escalate to architecture-auditor."
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$reason"
  exit 0
fi

# Allow (silent).
exit 0
