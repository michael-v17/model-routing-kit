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

# Risky path pattern. Default is zero-config (works out of the box). A project can override it
# by writing .claude/scope-guard.conf with key=value lines. Full-line `#` comments and blank
# lines are ignored. Two levels of key (Ticket 1 + Ticket 2):
#   RISKY=<regex>                      base pattern for any UI-only agent
#   RISKY_visual_polish=<regex>        per-agent override (visual-polish)
#   RISKY_text_and_copy_editor=<regex> per-agent override (text-and-copy-editor)
# Onboarding writes the conf — it never forks this script.
#
# Built-in defaults are DIFFERENTIATED per agent (Ticket 2): both UI agents are blocked from
# data/logic, but the copy editor is ALSO blocked from stylesheets — restyling is visual-polish's
# job, the copy editor is text/strings only. (Both can still edit text inside .tsx/.jsx markup.)
RISKY_DEFAULT_DATA='adapter|persistence|store|schema|migration|fixture|/api/|\.sql'
RISKY_DEFAULT_STYLE='\.css|\.scss|\.sass|\.less'
CONF="${CLAUDE_PROJECT_DIR:-.}/.claude/scope-guard.conf"

# conf_get KEY -> echoes the value of the last uncommented `KEY = value` line in CONF, or nothing.
conf_get() {
  [ -f "$CONF" ] || return 0
  sed -n "s/^[[:space:]]*$1[[:space:]]*=//p" "$CONF" 2>/dev/null \
    | tail -n1 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

# Resolve the RISKY pattern for THIS agent: per-agent conf key > base conf key > built-in default.
agent_key="RISKY_$(printf '%s' "$agent_type" | tr '-' '_')"   # visual-polish -> RISKY_visual_polish
RISKY="$(conf_get "$agent_key")"
[ -n "$RISKY" ] || RISKY="$(conf_get RISKY)"
if [ -z "$RISKY" ]; then
  case "$agent_type" in
    text-and-copy-editor) RISKY="$RISKY_DEFAULT_DATA|$RISKY_DEFAULT_STYLE" ;;
    *)                    RISKY="$RISKY_DEFAULT_DATA" ;;
  esac
fi

target="$file_path $command_str"

if [ "$ui_only" -eq 1 ] && printf '%s' "$target" | grep -Eiq "$RISKY"; then
  # Default escalation guidance (escalation agents assumed available).
  escalation="Escalate: visual-polish for styling/markup, architecture-auditor for data/logic."

  # Ticket 7 — never send the agent to a dead end. If the kit's escalation agents are NOT
  # registered (Ticket 6 failure mode), pointing at architecture-auditor would fail with
  # "Agent type not found", and the tempting "just do it inline" silently downgrades work the
  # ladder marked opus down to the driver tier. Switch to a SAFE-FALLBACK message instead.
  #
  # Gated on CLAUDE_PLUGIN_ROOT being set (i.e. a real plugin run) so the behavior tests, which
  # pipe raw payloads without a plugin root, keep their deterministic default message.
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/registration-check.sh" ]; then
    . "${CLAUDE_PLUGIN_ROOT}/hooks/registration-check.sh"
    if ! rk_agents_available "${CLAUDE_PROJECT_DIR:-$PWD}"; then
      escalation="SAFE FALLBACK — the kit's escalation agent (architecture-auditor, opus/xhigh) is NOT registered, so it cannot be invoked. Do this inline ONLY if your session is already AT OR ABOVE the required tier (data/logic ≈ opus). If the driver is below it, STOP and either raise it (/model opus) or reinstall the plugin — NEVER downgrade the task below the tier the ladder requires."
    fi
  fi

  reason="scope-guard: '$agent_type' tried to touch an out-of-scope path ($target). $escalation"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$reason"
  exit 0
fi

# Allow (silent).
exit 0
