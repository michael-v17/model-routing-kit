#!/usr/bin/env bash
# Install smoke test — proves model-routing-kit is a loadable Claude Code plugin,
# not just a folder of files. Validates manifests, hook wiring, agent frontmatter,
# and that every referenced file exists. No network, no global install side effects.
#
# Exit 0 = all checks pass. Run from anywhere.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
pass=0 fail=0

ok()   { printf 'PASS   | %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf 'FAIL   | %s\n' "$1"; fail=$((fail+1)); }

json_ok() { # path
  if command -v jq >/dev/null 2>&1; then jq -e . "$1" >/dev/null 2>&1
  else python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$1" >/dev/null 2>&1; fi
}

# 1. plugin.json is valid JSON and names the plugin
if json_ok "$ROOT/.claude-plugin/plugin.json"; then ok "plugin.json is valid JSON"; else bad "plugin.json is invalid JSON"; fi

# 2. marketplace.json is valid JSON
if json_ok "$ROOT/.claude-plugin/marketplace.json"; then ok "marketplace.json is valid JSON"; else bad "marketplace.json is invalid JSON"; fi

# 3. marketplace plugin name matches plugin.json name
if command -v jq >/dev/null 2>&1; then
  pn="$(jq -r '.name' "$ROOT/.claude-plugin/plugin.json")"
  mn="$(jq -r '.plugins[0].name' "$ROOT/.claude-plugin/marketplace.json")"
  [ "$pn" = "$mn" ] && ok "marketplace plugin name matches plugin.json ($pn)" || bad "name mismatch: plugin.json=$pn marketplace=$mn"
else
  ok "name-match check skipped (jq absent)"
fi

# 4. hooks.json is valid JSON and references the guard script
if json_ok "$ROOT/hooks/hooks.json" && grep -q 'scope-guard.sh' "$ROOT/hooks/hooks.json"; then
  ok "hooks.json valid and wires scope-guard.sh"
else bad "hooks.json invalid or missing scope-guard.sh reference"; fi

# 5. scope-guard.sh exists and is executable
[ -x "$ROOT/hooks/scope-guard.sh" ] && ok "scope-guard.sh is executable" || bad "scope-guard.sh missing or not executable"

# 6. every agent file has the required frontmatter keys
agents_ok=1
for f in "$ROOT"/agents/*.md; do
  for key in name description model; do
    grep -q "^$key:" "$f" || { bad "agent $(basename "$f") missing '$key:'"; agents_ok=0; }
  done
done
[ "$agents_ok" -eq 1 ] && ok "all agents have name/description/model frontmatter"

# 7. CLAUDE.template.md and onboard command present
[ -f "$ROOT/CLAUDE.template.md" ] && [ -f "$ROOT/commands/onboard.md" ] \
  && ok "CLAUDE.template.md and commands/onboard.md present" \
  || bad "CLAUDE.template.md or commands/onboard.md missing"

# 8. scope-guard behavior suite still green
if bash "$ROOT/hooks/scope-guard.test.sh" | grep -q 'FAIL'; then
  bad "scope-guard.test.sh has failing cases"
else ok "scope-guard.test.sh all green"; fi

# 9. /run-at command present and wires the manual ledger (Ticket 5A)
runat="$ROOT/commands/run-at.md"
if [ -f "$runat" ] && grep -q 'routing-log.jsonl' "$runat" && grep -q '"source":"manual"' "$runat"; then
  ok "run-at command present and logs source:\"manual\" to routing-log.jsonl"
else bad "run-at command missing or does not log the manual choice"; fi

# 10. intermediate implementer agent present at the correct tier (Ticket 5B)
impl="$ROOT/agents/implementer.md"
if [ -f "$impl" ] && grep -q '^model: *sonnet' "$impl" && grep -q '^effort: *high' "$impl"; then
  ok "implementer agent present at sonnet/high (intermediate rung)"
else bad "implementer agent missing or not sonnet/high"; fi

printf -- '----\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
