#!/usr/bin/env bash
# Tests for the registration self-check (Ticket 6) and the safe escalation fallback (Ticket 7).
#
# Covers:
#   (a) marketplace absent  -> SessionStart self-check WARNS (enabled != registered)
#   (a') fully registered   -> self-check stays SILENT
#   (b) escalation agent missing -> scope-guard message does NOT degrade below the required tier
#                                   (it tells the agent to STOP/raise, never to downgrade)
#   (b') escalation agent present -> scope-guard uses the normal escalate message
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
SELFCHECK="$DIR/session-regcheck.sh"
GUARD="$DIR/scope-guard.sh"
pass=0 fail=0
ok()  { printf 'PASS   | %s\n' "$1"; pass=$((pass+1)); }
bad() { printf 'FAIL   | %s\n' "$1"; fail=$((fail+1)); }

# --- fixtures: fake CLAUDE_CONFIG_DIRs ----------------------------------------------------------
PROJ="/Users/example/proj-under-test"

# 1) config dir with NO kit marketplace and NO kit plugin (the eviction failure mode).
EMPTY_CFG="$(mktemp -d)"
mkdir -p "$EMPTY_CFG/plugins"
cat > "$EMPTY_CFG/plugins/known_marketplaces.json" <<'EOF'
{ "claude-plugins-official": { "source": { "source": "github", "repo": "anthropics/claude-plugins-official" } } }
EOF
cat > "$EMPTY_CFG/plugins/installed_plugins.json" <<'EOF'
{ "version": 2, "plugins": { "frontend-design@claude-plugins-official": [ { "scope": "project", "projectPath": "/some/other/repo" } ] } }
EOF

# 2) config dir where the kit is fully registered for THIS project.
GOOD_CFG="$(mktemp -d)"
mkdir -p "$GOOD_CFG/plugins"
cat > "$GOOD_CFG/plugins/known_marketplaces.json" <<'EOF'
{ "model-routing-kit": { "source": { "source": "github", "repo": "michael-v17/model-routing-kit" } } }
EOF
cat > "$GOOD_CFG/plugins/installed_plugins.json" <<EOF
{ "version": 2, "plugins": { "model-routing-kit@model-routing-kit": [ { "scope": "project", "projectPath": "$PROJ" } ] } }
EOF

# A UI-only deny payload (visual-polish touches a data adapter -> normally DENY + escalate text).
DENY_PAYLOAD='{"agent_type":"visual-polish","tool_name":"Edit","tool_input":{"file_path":"src/data/userAdapter.ts"}}'

# --- (a) Ticket 6: marketplace absent -> self-check warns ---------------------------------------
P1="$(mktemp -d)"
out="$(printf '{"cwd":"%s"}' "$P1" | CLAUDE_PROJECT_DIR="$P1" CLAUDE_CONFIG_DIR="$EMPTY_CFG" CLAUDE_PLUGIN_ROOT="$ROOT" bash "$SELFCHECK")"
if printf '%s' "$out" | grep -q 'enabled ≠ registered'; then
  ok "self-check WARNS when the kit marketplace is absent"
else
  bad "self-check did NOT warn on absent marketplace (got: $out)"
fi

# The warning must carry the fix (re-add marketplace + reinstall) and the user/global advice.
if printf '%s' "$out" | grep -q 'marketplace add' && printf '%s' "$out" | grep -qi 'USER/GLOBAL'; then
  ok "warning includes the fix (re-add marketplace + reinstall at user/global scope)"
else
  bad "warning missing the fix or the user/global-scope recommendation"
fi

# The warning must derive the expected agents from agents/*.md (no hardcoded list drift).
if printf '%s' "$out" | grep -q 'complex-implementer' && printf '%s' "$out" | grep -q 'architecture-auditor'; then
  ok "warning lists the kit's expected agents (derived from agents/*.md)"
else
  bad "warning did not list the expected agents"
fi

# --- (a') fully registered -> self-check stays silent ------------------------------------------
P2="$(mktemp -d)"
out="$(printf '{"cwd":"%s"}' "$PROJ" | CLAUDE_PROJECT_DIR="$PROJ" CLAUDE_CONFIG_DIR="$GOOD_CFG" CLAUDE_PLUGIN_ROOT="$ROOT" bash "$SELFCHECK")"
if [ -z "$out" ]; then
  ok "self-check is SILENT when the kit is fully registered for this project"
else
  bad "self-check warned despite healthy registration (got: $out)"
fi

# --- (b) Ticket 7: escalation agent missing -> message must NOT degrade below required tier -----
out="$(printf '%s' "$DENY_PAYLOAD" | CLAUDE_PROJECT_DIR="$PROJ" CLAUDE_CONFIG_DIR="$EMPTY_CFG" CLAUDE_PLUGIN_ROOT="$ROOT" bash "$GUARD")"
if printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then
  ok "scope-guard still DENIES the out-of-scope edit when escalation agent is missing"
else
  bad "scope-guard failed to deny (got: $out)"
fi
if printf '%s' "$out" | grep -qi 'NEVER downgrade' && printf '%s' "$out" | grep -qi 'STOP'; then
  ok "missing-agent message tells the agent to STOP/raise tier, never downgrade"
else
  bad "missing-agent message does not enforce the no-downgrade rule (got: $out)"
fi
# It must NOT quietly send the agent to the now-nonexistent architecture-auditor as if available.
if printf '%s' "$out" | grep -q 'SAFE FALLBACK'; then
  ok "missing-agent message switches to the SAFE FALLBACK wording"
else
  bad "missing-agent message did not switch to safe-fallback wording (got: $out)"
fi

# --- (b') escalation agent present -> normal escalate message ----------------------------------
out="$(printf '%s' "$DENY_PAYLOAD" | CLAUDE_PROJECT_DIR="$PROJ" CLAUDE_CONFIG_DIR="$GOOD_CFG" CLAUDE_PLUGIN_ROOT="$ROOT" bash "$GUARD")"
if printf '%s' "$out" | grep -q '"permissionDecision":"deny"' \
   && printf '%s' "$out" | grep -q 'architecture-auditor for data/logic' \
   && ! printf '%s' "$out" | grep -q 'SAFE FALLBACK'; then
  ok "registered case uses the normal escalate message (no safe-fallback noise)"
else
  bad "registered case did not use the normal escalate message (got: $out)"
fi

rm -rf "$EMPTY_CFG" "$GOOD_CFG" "$P1" "$P2"
printf -- '----\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
