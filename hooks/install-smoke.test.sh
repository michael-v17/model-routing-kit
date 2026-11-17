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

# ── Running a sub-suite: DO NOT pipe it ──────────────────────────────────────
# This file runs with `set -uo pipefail`. The obvious form
#     if bash sub.test.sh | grep -q 'FAIL'; then bad; else ok; fi
# is BROKEN under pipefail: a failing sub-suite exits non-zero, pipefail makes the whole
# pipeline non-zero, the `if` takes the else branch — and the gate prints PASS *because* the
# sub-suite failed. Found 2026-08-07; all six sub-checks had it. install-smoke is the command
# the README tells you to run before trusting an install, so it was green exactly when it
# should have been red.
#
# Capture first, then test — and trust the exit code, not just the word FAIL.
sub_suite() {                      # sub_suite <path> <label>
  local path="$1" label="$2" out rc
  out="$(bash "$path" 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ] || printf '%s\n' "$out" | grep -q '^FAIL'; then
    bad "$label has failing cases (exit $rc)"
  else
    ok "$label all green"
  fi
}

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
sub_suite "$ROOT/hooks/scope-guard.test.sh" "scope-guard.test.sh"

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

# 11. SessionStart registration self-check wired and executable (Ticket 6)
selfcheck="$ROOT/hooks/session-regcheck.sh"
if grep -q 'SessionStart' "$ROOT/hooks/hooks.json" \
   && grep -q 'session-regcheck.sh' "$ROOT/hooks/hooks.json" \
   && [ -x "$selfcheck" ] && [ -x "$ROOT/hooks/registration-check.sh" ]; then
  ok "SessionStart self-check wired in hooks.json and scripts executable (Ticket 6)"
else bad "registration self-check not wired or scripts not executable"; fi

# 12. registration self-check behavior suite still green (Tickets 6 & 7)
sub_suite "$ROOT/hooks/registration-check.test.sh" "registration-check.test.sh"

# 13. PostToolUse Agent telemetry wired and executable (Ticket 4, cost half)
telem="$ROOT/hooks/agent-telemetry.sh"
if grep -q 'PostToolUse' "$ROOT/hooks/hooks.json" \
   && grep -q 'agent-telemetry.sh' "$ROOT/hooks/hooks.json" \
   && grep -q '"matcher": *"Agent"' "$ROOT/hooks/hooks.json" \
   && [ -x "$telem" ]; then
  ok "PostToolUse Agent telemetry wired in hooks.json and script executable (Ticket 4)"
else bad "agent telemetry hook not wired on the Agent matcher, or script not executable"; fi

# 14. telemetry behavior suite still green (Ticket 4)
sub_suite "$ROOT/hooks/agent-telemetry.test.sh" "agent-telemetry.test.sh"

# 13b. the escalation ladder is one string, byte-identical everywhere it appears.
# It drifted: commands/route.md was missing the `sonnet/xhigh` rung that USAGE.md calls
# load-bearing — and /route is the thing that PICKS the tier, so it could not pick a rung the
# docs told you to prefer. CLAUDE.template.md is the canonical copy (it's what /onboard installs).
canon="$(grep -ho 'sonnet/low →[^—]*opus/xhigh' "$ROOT/CLAUDE.template.md" | head -n1 | sed 's/[[:space:]]*$//')"
if [ -z "$canon" ]; then
  bad "no ladder string found in CLAUDE.template.md — the canonical copy is missing"
else
  offenders=""
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    f="${hit%%:*}"; rest="${hit#*:}"; ln="${rest%%:*}"
    got="$(printf '%s' "${rest#*:}" | grep -o 'sonnet/low →[^—]*opus/xhigh' | head -n1 | sed 's/[[:space:]]*$//')"
    [ "$got" = "$canon" ] || offenders="$offenders ${f#$ROOT/}:$ln"
  done <<EOF
$(grep -rn 'sonnet/low →' "$ROOT" --include='*.md' 2>/dev/null | grep -v '/\.git/' | grep -v 'BACKLOG.md')
EOF
  if [ -n "$offenders" ]; then
    bad "ladder string differs from CLAUDE.template.md at:$offenders"
  else ok "escalation ladder byte-identical across all docs (BACKLOG excluded as a dated ledger)"; fi
fi

# 14a. the docs' test counts match what the suites actually print (drifted to 4 wrong values
# across 3 files before this check existed). Guarded against recursion: docs-counts runs THIS
# suite to learn its own number, so it sets RK_SKIP_DOCS_COUNTS when it does.
if [ "${RK_SKIP_DOCS_COUNTS:-}" = "1" ]; then
  ok "docs-counts.test.sh skipped (invoked from it — recursion guard)"
else
  sub_suite "$ROOT/hooks/docs-counts.test.sh" "docs-counts.test.sh (doc test-counts match reality)"
fi

# 14b. the three version fields stay in sync (they drifted once — commit 9747a0a)
pv="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$ROOT/.claude-plugin/plugin.json" | head -n1)"
mv1="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$ROOT/.claude-plugin/marketplace.json" | head -n1)"
mv2="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$ROOT/.claude-plugin/marketplace.json" | sed -n 2p)"
if [ -n "$pv" ] && [ "$pv" = "$mv1" ] && [ "$pv" = "$mv2" ]; then
  ok "version in sync across plugin.json + both marketplace.json fields ($pv)"
else bad "version drift: plugin.json=$pv marketplace.metadata=$mv1 marketplace.plugins[0]=$mv2"; fi

# 15. routing-table guard wired + green (Ticket 17)
rtc="$ROOT/hooks/routing-table-check.sh"
if [ -x "$rtc" ] && grep -q 'routing-table-check.sh' "$ROOT/hooks/hooks.json"; then
  ok "routing-table-check.sh executable and wired on SessionStart (Ticket 17)"
else bad "routing-table-check.sh missing, not executable, or not wired in hooks.json"; fi

sub_suite "$ROOT/hooks/routing-table-check.test.sh" "routing-table-check.test.sh"

# 16. shipped workflows present (Ticket 16)
if [ -f "$ROOT/workflows/audit.js" ] && [ -f "$ROOT/workflows/migrate.js" ] \
   && [ -f "$ROOT/workflows/probe.js" ] && [ -f "$ROOT/workflows/README.md" ]; then
  ok "workflows/ ships audit, migrate, probe (+ README)"
else bad "workflows/ is missing one of audit.js / migrate.js / probe.js / README.md"; fi

# 16. the rule the kit preaches, mechanized: no unrouted stage (Tickets 10 + 16)
sub_suite "$ROOT/workflows/routing-lint.test.sh" "routing-lint.test.sh (every agent() stage declares a tier)"

# LAST: prove the sub-suite runner actually propagates a failure. Without this, the bug above
# is invisible again the moment someone "simplifies" sub_suite back into a pipe.
_stub="$(mktemp)"; printf '#!/usr/bin/env bash\nprintf "FAIL   | deliberate\\n"\nexit 1\n' > "$_stub"
_before_fail=$fail
sub_suite "$_stub" "__propagation-selftest__" >/dev/null 2>&1
rm -f "$_stub"
if [ "$fail" -gt "$_before_fail" ]; then
  fail=$_before_fail   # the stub was supposed to fail; don't count it against the run
  ok "sub-suite failures propagate (a failing sub-suite is reported as FAIL, not swallowed)"
else
  bad "sub_suite() SWALLOWED a failing suite — the gate would report green while a suite is red"
fi

printf -- '----\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
