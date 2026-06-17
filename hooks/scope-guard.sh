#!/usr/bin/env bash
# PreToolUse scope-guard — feasibility probe for the agent-routing-kit.
# Reads a Claude Code PreToolUse hook payload on stdin and decides allow/deny.
#
# Policy: if the ACTIVE subagent is a UI-only agent (visual-polish / text-and-copy-editor)
# and the tool would touch a RISKY path, block it and tell the agent to escalate. Otherwise allow.
# RISKY defaults to a frontend pattern but is configurable per project via
# .claude/scope-guard.conf (key=value); see the RISKY block below.
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

# Risky path pattern. Default is zero-config (works out of the box). A project can override
# it by writing .claude/scope-guard.conf with key=value lines, e.g. `RISKY=<regex>`. Full-line
# `#` comments and blank lines are ignored. The key=value format (not a bare regex) is so
# Ticket 2 can add per-agent keys (RISKY_visual_polish=... / RISKY_text_and_copy_editor=...)
# later without changing this parser. Onboarding writes the conf — it never forks this script.
RISKY_DEFAULT='adapter|persistence|store|schema|migration|fixture|/api/|\.sql'
CONF="${CLAUDE_PROJECT_DIR:-.}/.claude/scope-guard.conf"

# conf_get KEY -> echoes the value of the last uncommented `KEY = value` line in CONF, or nothing.
conf_get() {
  [ -f "$CONF" ] || return 0
  sed -n "s/^[[:space:]]*$1[[:space:]]*=//p" "$CONF" 2>/dev/null \
    | tail -n1 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

RISKY="$(conf_get RISKY)"
[ -n "$RISKY" ] || RISKY="$RISKY_DEFAULT"

target="$file_path $command_str"

if [ "$ui_only" -eq 1 ] && printf '%s' "$target" | grep -Eiq "$RISKY"; then
  reason="scope-guard: '$agent_type' is UI-only but tried to touch a data/logic path ($target). Escalate to architecture-auditor."
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$reason"
  exit 0
fi

# Allow (silent).
exit 0
