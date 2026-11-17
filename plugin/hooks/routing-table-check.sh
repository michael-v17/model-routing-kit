#!/usr/bin/env bash
# Ticket 17 — does the routing table name agents that actually resolve?
#
# THE FAILURE THIS CATCHES, and why the existing guards miss it:
#   session-regcheck.sh asks "is the PLUGIN registered?" — a yes/no about the kit.
#   This asks a different question: "every agent NAMED in this project's routing table,
#   does it resolve from here?" Those come apart constantly, because a project can vendor
#   its own tuned agents into .claude/agents/ (the kit's own law: per-project tuning is the
#   irreducible cost) and vendor only SOME of them, while the table keeps routing to all.
#   Measured case, a production repo 2026-08-07: the table routed to five agents, .claude/agents/
#   held two, the plugin was installed under a DIFFERENT CLAUDE_CONFIG_DIR, and the first
#   symptom was an escalation dying mid-task with "Agent type not found".
#
# WHY IT ALSO RUNS STANDALONE (this is the point, not a convenience):
#   Ticket 13's lesson is that a guard shipped inside the plugin cannot warn you about the
#   plugin being absent — when it matters most, it isn't running. So this file works two ways:
#     as a hook      : SessionStart, wired via hooks.json, quiet when healthy
#     as a command   : bash routing-table-check.sh [project-dir] [--verbose]
#   Run it by hand in any project, under any config dir, plugin or no plugin.
#
# Always exits 0 as a hook. Never blocks. "Can't tell" is reported as can't-tell, never as OK.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
[ -f "$DIR/registration-check.sh" ] && . "$DIR/registration-check.sh"

STANDALONE=0
VERBOSE=0
proj_arg=""
for a in "$@"; do
  case "$a" in
    --verbose|-v) VERBOSE=1; STANDALONE=1 ;;
    --*) ;;
    *) proj_arg="$a"; STANDALONE=1 ;;
  esac
done
[ -t 1 ] && STANDALONE=1

payload=""
[ "$STANDALONE" -eq 0 ] && payload="$(cat 2>/dev/null || true)"

proj="$proj_arg"
[ -n "$proj" ] || proj="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$proj" ] && [ -n "$payload" ] && command -v jq >/dev/null 2>&1; then
  proj="$(printf '%s' "$payload" | jq -r '.cwd // ""' 2>/dev/null || true)"
fi
[ -n "$proj" ] || proj="$PWD"
proj="${proj%/}"

# ── 1. Where is the routing table? ──────────────────────────────────────────
# CLAUDE.local.md is checked first: it's the personal, gitignored edition, and when both
# exist it is the one that actually describes this machine.
table=""
for cand in "$proj/CLAUDE.local.md" "$proj/CLAUDE.md" "$proj/.claude/CLAUDE.md"; do
  if [ -f "$cand" ] && grep -qiE '^#+ *routing|model-routing policy' "$cand" 2>/dev/null; then
    table="$cand"; break
  fi
done

if [ -z "$table" ]; then
  [ "$STANDALONE" -eq 1 ] && echo "no routing table found in $proj (looked at CLAUDE.local.md, CLAUDE.md, .claude/CLAUDE.md) — nothing to check"
  exit 0
fi

# ── 2. Which agents does it NAME? ───────────────────────────────────────────
# Two shapes are in the wild and both are load-bearing:
#   CLAUDE.local.md (hand-tuned):  "→ **architecture-auditor** (opus, xhigh)"
#   CLAUDE.template.md (shipped):  "→ architecture-auditor (opus)"
# Bold is the project's own emphasis convention, so a bold slug counts as a candidate.
# A PLAIN slug counts only if it matches an agent the kit actually defines — otherwise
# "→ main session", "→ opus", "→ Workflow tool" all read as agent names and the check
# turns into noise. A guard that cries wolf gets muted, which is worse than no guard.
routing_lines="$(awk '
  /^#+ *[Rr]outing/         { inside=1; next }
  /^#+ /                    { if (inside && $0 !~ /[Rr]outing/) inside=0 }
  inside                    { print }
' "$table")"

# Canonical names the kit defines — readable straight off disk, so this works even when the
# plugin is not registered (which is exactly when this check matters most).
canonical="$(rk_expected_agents 2>/dev/null || true)"
if [ -z "$canonical" ]; then
  for f in "$DIR"/../agents/*.md; do
    [ -f "$f" ] || continue
    sed -n 's/^name:[[:space:]]*//p' "$f" | head -n1
  done > /tmp/.rk_canon.$$ 2>/dev/null || true
  canonical="$(cat /tmp/.rk_canon.$$ 2>/dev/null || true)"; rm -f /tmp/.rk_canon.$$
fi

# Not agents, however they are written: modes, tiers, aliases, prose.
DENY='ultracode|built-in|builtin|main|session|opus|sonnet|haiku|fable|opusplan|inherit|best|workflow|the|let|try|run-at|model|code-review'

# Scan the WHOLE routing line, not just the token glued to the arrow — real tables put the
# agent mid-sentence: "→ opusplan, or architecture-auditor (opus) first" would otherwise
# report `opusplan` and miss the agent entirely.
bold="$(printf '%s\n' "$routing_lines" \
  | grep -oE '\*\*[a-z][a-z0-9-]{2,}\*\*' | sed 's/\*//g' | sort -u)"

# Plain (unbolded) names are only trusted when they exactly match an agent the kit defines.
# Whole-word match, so `implementer` does not also fire on `complex-implementer`.
plain=""
while IFS= read -r c; do
  [ -n "$c" ] || continue
  printf '%s\n' "$routing_lines" | grep -qE "(^|[^a-z0-9-])${c}([^a-z0-9-]|\$)" && plain="$plain$c"$'\n'
done <<< "$canonical"

named="$(printf '%s\n%s\n' "$bold" "$plain" | sed '/^$/d' | grep -vExi "$DENY" | sort -u)"

if [ -z "$named" ]; then
  [ "$STANDALONE" -eq 1 ] && echo "routing table at $table names no agents in the '→ name' shape — nothing to check"
  exit 0
fi

# ── 3. What resolves from here? ─────────────────────────────────────────────
local_agents=""
if [ -d "$proj/.claude/agents" ]; then
  for f in "$proj"/.claude/agents/*.md; do
    [ -f "$f" ] || continue
    n="$(sed -n 's/^name:[[:space:]]*//p' "$f" | head -n1)"
    [ -n "$n" ] || n="$(basename "$f" .md)"
    local_agents="$local_agents$n"$'\n'
  done
fi

plugin_ok=1
plugin_agents=""
if command -v rk_agents_available >/dev/null 2>&1; then
  rk_agents_available "$proj" && plugin_ok=0
  plugin_agents="$(rk_expected_agents 2>/dev/null || true)"
fi

has() { printf '%s\n' "$2" | grep -qx -- "$1"; }

# Built-ins always resolve; they need no plugin and no vendored file. (They do come with a
# cost trap of their own inside workflows — no `model:` of their own, so they run at the
# driver's tier — but that is routing-lint's department, not this one's.)
BUILTINS=$'explore\nplan\ngeneral-purpose\nstatusline-setup'

missing=""; via_plugin=""; via_local=""; via_builtin=""
while IFS= read -r a; do
  [ -n "$a" ] || continue
  if has "$a" "$local_agents"; then
    via_local="$via_local$a "
  elif has "$(printf '%s' "$a" | tr 'A-Z' 'a-z')" "$BUILTINS"; then
    via_builtin="$via_builtin$a "
  elif [ "$plugin_ok" -eq 0 ] && has "$a" "$plugin_agents"; then
    via_plugin="$via_plugin$a "
  else
    missing="$missing$a "
  fi
done <<< "$named"

cfg="$(command -v rk_config_dir >/dev/null 2>&1 && rk_config_dir || printf '%s' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}")"

# ── 4. Report ───────────────────────────────────────────────────────────────
if [ "$STANDALONE" -eq 1 ]; then
  echo "routing table : $table"
  echo "config dir    : $cfg"
  echo "plugin        : $([ "$plugin_ok" -eq 0 ] && echo 'registered for this project' || echo 'NOT registered here')"
  echo
  [ -n "$via_local" ]   && echo "✅ project-tuned (.claude/agents/): $via_local"
  [ -n "$via_plugin" ]  && echo "✅ via plugin (generic, not project-tuned): $via_plugin"
  [ -n "$via_builtin" ] && echo "✅ built-in: $via_builtin"
  if [ -n "$missing" ]; then
    echo "🔴 NAMED IN THE TABLE BUT UNRESOLVABLE: $missing"
    echo
    echo "   Escalating to any of those dies mid-task with \"Agent type not found\", and the"
    echo "   routing table says STOP rather than downgrade — so the task stalls."
    echo "   Fix either way:"
    echo "     a) install the kit in THIS config dir  → generic agents, every project:"
    echo "          /plugin marketplace add <path-to-model-routing-kit>"
    echo "          /plugin install model-routing-kit@model-routing-kit   (user scope)"
    echo "     b) vendor + tune them into $proj/.claude/agents/ → project-specific, survives"
    echo "        any config-dir split. Start from the kit's agents/*.md and tune the"
    echo "        description, tools and scope to this project."
    echo "   Then RESTART the session: agents register at session start, so a file written"
    echo "   now does not exist in the session that wrote it."
  else
    echo "— every agent named in the routing table resolves."
  fi
  [ "$VERBOSE" -eq 1 ] && { echo; echo "named in table:"; printf '%s\n' "$named" | sed 's/^/  /'; }
  [ -n "$missing" ] && exit 1
  exit 0
fi

# Hook mode: silent when healthy, warn-once per signature when not.
[ -n "$missing" ] || exit 0

stamp="$proj/.claude/.routing-table-check"
sig="missing=$(printf '%s' "$missing" | tr -s ' ') cfg=$cfg"
if [ -f "$stamp" ] && [ "$(cat "$stamp" 2>/dev/null || true)" = "$sig" ]; then
  exit 0
fi
mkdir -p "$proj/.claude" 2>/dev/null || true
printf '%s' "$sig" > "$stamp" 2>/dev/null || true

msg="⚠️ model-routing-kit: this project's routing table (${table##*/}) routes to agents that do NOT resolve here: ${missing}."
msg="$msg Escalating to any of them fails with 'Agent type not found', and the table's own rule is STOP-never-downgrade — so the task stalls mid-flight."
if [ "$plugin_ok" -ne 0 ]; then
  msg="$msg The kit's plugin is NOT registered under this config dir (${cfg}), so it can't supply generic fallbacks either."
  msg="$msg FIX (a): \`/plugin marketplace add <path-to-model-routing-kit>\` then \`/plugin install model-routing-kit@model-routing-kit\` at USER scope."
else
  msg="$msg The plugin IS registered but does not define these names — they are project-local agents that were never vendored."
fi
msg="$msg FIX (b): copy the missing agents into ${proj}/.claude/agents/ and tune them to this project (tools, scope, description)."
msg="$msg EITHER WAY the session must be RESTARTED afterwards — agents register at session start, so a file written now does not exist in the session that wrote it."
msg="$msg UNTIL FIXED: do not silently run escalated work on a smaller model. If this session is already at or above the required tier, do it inline and say so; otherwise stop and ask."

if command -v jq >/dev/null 2>&1; then
  jq -nc --arg m "$msg" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$m}}'
else
  printf '%s\n' "$msg"
fi
exit 0
