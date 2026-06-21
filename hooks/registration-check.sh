#!/usr/bin/env bash
# Shared registration-check helpers for model-routing-kit (Tickets 6 & 7).
#
# Sourced by:
#   - hooks/session-regcheck.sh         (SessionStart — warns when enabled != registered)
#   - hooks/scope-guard.sh              (conditions the escalation message on registration)
#
# WHY THIS EXISTS: a plugin can be `enabled: true` in settings.json yet have ZERO agents
# registered. CLAUDE_CONFIG_DIR is shared across projects, so plugin churn in a sibling repo
# can rewrite the shared registry (known_marketplaces.json / installed_plugins.json) and evict
# this kit's marketplace. The `enabled` flag stays true; the marketplace that resolves it is
# gone; the agents never register → escalation fails with "Agent type not found". settings.json
# alone can't tell you this — the registry files can.
#
# Every function here is BEST-EFFORT and quiet: missing tools or files mean "can't tell"
# (return non-zero), never a crash. Callers decide what to do with an unknown.

# Names that must match .claude-plugin/plugin.json + marketplace.json.
RK_PLUGIN_NAME="model-routing-kit"
RK_MARKETPLACE_NAME="model-routing-kit"

# The Claude Code config dir that holds the plugin registry (shared across projects).
rk_config_dir() {
  printf '%s' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
}

# Expected agent names, DERIVED from agents/*.md (never hardcoded). One name per line.
rk_expected_agents() {
  local root="${CLAUDE_PLUGIN_ROOT:-}"
  [ -n "$root" ] || root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  local f
  for f in "$root"/agents/*.md; do
    [ -f "$f" ] || continue
    sed -n 's/^name:[[:space:]]*//p' "$f" | head -n1
  done
}

# Is the kit's marketplace present in known_marketplaces.json? 0 = yes, 1 = no/unknown.
rk_marketplace_registered() {
  local km; km="$(rk_config_dir)/plugins/known_marketplaces.json"
  [ -f "$km" ] || return 1
  if command -v jq >/dev/null 2>&1; then
    jq -e --arg n "$RK_MARKETPLACE_NAME" 'has($n)' "$km" >/dev/null 2>&1
  else
    grep -q "\"$RK_MARKETPLACE_NAME\"[[:space:]]*:" "$km"
  fi
}

# Is the kit plugin registered AND applicable to this project? 0 = yes, 1 = no/unknown.
# Applicable = an entry with user/global scope (applies everywhere) OR an entry whose
# projectPath matches this project dir. A scope local/project entry for a SIBLING repo does
# not count — that's exactly the failure mode we're guarding against.
rk_plugin_registered() {
  local proj="${1:-${CLAUDE_PROJECT_DIR:-$PWD}}"
  proj="${proj%/}"   # normalize: a trailing slash must not cause a false "not registered"
  local ip; ip="$(rk_config_dir)/plugins/installed_plugins.json"
  [ -f "$ip" ] || return 1
  local key="${RK_PLUGIN_NAME}@${RK_MARKETPLACE_NAME}"
  if command -v jq >/dev/null 2>&1; then
    jq -e --arg k "$key" --arg p "$proj" '
      (.plugins[$k] // []) as $entries
      | ($entries | any(.scope == "user" or .scope == "global"))
        or ($entries | any((.projectPath | rtrimstr("/")) == $p))
    ' "$ip" >/dev/null 2>&1
  else
    # No jq: coarse check — the plugin key exists somewhere in the file.
    grep -q "\"$key\"" "$ip"
  fi
}

# Convenience: is the kit fully resolvable for this project (marketplace + plugin)? 0/1.
rk_agents_available() {
  rk_marketplace_registered && rk_plugin_registered "${1:-}"
}
