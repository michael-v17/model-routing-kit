#!/usr/bin/env bash
# SessionStart hook (Ticket 6) — warn LOUDLY when the kit is enabled but NOT registered.
#
# enabled != registered: settings.json may list this plugin as on, but a shared CLAUDE_CONFIG_DIR
# means a sibling repo's plugin activity can evict our marketplace from the shared registry.
# Then the agents silently fail to register and the FIRST sign is an escalation dying with
# "Agent type 'complex-implementer' not found". This check reads the registry files at session
# start and surfaces the gap up front — with the exact fix — instead of failing on escalation.
#
# Noise control: warn-once per distinct problem (a stamp file under the project's .claude/).
# When registration is healthy again the stamp is cleared, so a recurrence warns afresh.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/registration-check.sh"

payload="$(cat 2>/dev/null || true)"

# Resolve the project dir: env var first, then the SessionStart payload's cwd, then PWD.
proj="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$proj" ] && command -v jq >/dev/null 2>&1; then
  proj="$(printf '%s' "$payload" | jq -r '.cwd // ""' 2>/dev/null || true)"
fi
[ -n "$proj" ] || proj="$PWD"

mkt=1; rk_marketplace_registered && mkt=0
plg=1; rk_plugin_registered "$proj" && plg=0

stamp="$proj/.claude/.routing-kit-regcheck"

# Healthy: clear the warn-once stamp (re-arm) and stay silent.
if [ "$mkt" -eq 0 ] && [ "$plg" -eq 0 ]; then
  rm -f "$stamp" 2>/dev/null || true
  exit 0
fi

# Warn once per distinct problem signature (so we're not noisy every single session).
sig="mkt=$mkt plg=$plg cfg=$(rk_config_dir)"
if [ -f "$stamp" ] && [ "$(cat "$stamp" 2>/dev/null || true)" = "$sig" ]; then
  exit 0
fi
mkdir -p "$proj/.claude" 2>/dev/null || true
printf '%s' "$sig" > "$stamp" 2>/dev/null || true

agents="$(rk_expected_agents | paste -sd , - 2>/dev/null | sed 's/,/, /g' || true)"
[ -n "$agents" ] || agents="complex-implementer, architecture-auditor, implementer, visual-polish, text-and-copy-editor"
cfg="$(rk_config_dir)"

msg="⚠️ model-routing-kit: enabled ≠ registered — the kit's agents will NOT load this session."
if [ "$mkt" -ne 0 ]; then
  msg="$msg The kit's marketplace is MISSING from ${cfg}/plugins/known_marketplaces.json."
else
  msg="$msg The marketplace is present but the plugin is NOT registered for THIS project (${proj}) in ${cfg}/plugins/installed_plugins.json."
fi
msg="$msg Expected agents (${agents}) are unavailable, so any escalation to them fails with 'Agent type not found'."
msg="$msg LIKELY CAUSE: CLAUDE_CONFIG_DIR (${cfg}) is shared across projects and a sibling repo's plugin churn evicted this kit from the registry — \`enabled: true\` in settings.json does not mean registered."
msg="$msg FIX: re-add the local marketplace and reinstall — \`/plugin marketplace add <path-to-model-routing-kit>\` then \`/plugin install model-routing-kit@model-routing-kit\`."
msg="$msg Install at USER/GLOBAL scope so a sibling repo's churn can't evict it again."
msg="$msg UNTIL FIXED: do NOT silently downgrade escalated work — if your session isn't already at the required tier, stop and raise /model rather than running it on a smaller model."

# SessionStart: additionalContext is injected into the session so the assistant surfaces it.
if command -v jq >/dev/null 2>&1; then
  jq -nc --arg m "$msg" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$m}}'
else
  printf '%s\n' "$msg"
fi
exit 0
