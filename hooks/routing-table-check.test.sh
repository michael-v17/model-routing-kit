#!/usr/bin/env bash
# Behavior suite for routing-table-check.sh (Ticket 17).
#
# Each case builds a throwaway project and asserts the CLASSIFICATION, not just the exit code —
# "it warned" is not the same as "it warned about the right agent", and the difference is the
# whole value of the guard. Case 3 is the one that matters most: a guard that flags "→ main
# session" or "→ ultracode" as a missing agent gets muted within a week, and a muted guard is
# indistinguishable from no guard.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK="$DIR/routing-table-check.sh"
pass=0; fail=0
ok()  { printf 'PASS   | %s\n' "$1"; pass=$((pass+1)); }
bad() { printf 'FAIL   | %s\n' "$1"; fail=$((fail+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkproj() {                      # mkproj <name> <table-filename>
  local p="$TMP/$1"; mkdir -p "$p/.claude/agents"; printf '%s' "$p"
}
addagent() {                    # addagent <proj> <name>
  printf -- '---\nname: %s\ndescription: fixture\nmodel: sonnet\ntools: Read\n---\nfixture\n' "$2" \
    > "$1/.claude/agents/$2.md"
}

TABLE_BOLD='# model-routing policy

## Routing (fixture)
- Read-only discovery → let the built-in Explore subagent handle it.
- Copy/strings only → **text-and-copy-editor** (haiku)
- UI polish → **visual-polish** (sonnet, effort low)
- Normal impl → main session (sonnet)
- Moderately hard → **implementer** (sonnet, effort high)
- Hard → **complex-implementer** (opus, effort high)
- Risky → **architecture-auditor** (opus, xhigh, read-only) first, then implement
- Breadth → **ultracode** (type `ultracode` in the prompt)

## Ladder
sonnet/low → opus/xhigh.
'

TABLE_PLAIN='# model-routing policy

## Routing
- Text/copy/labels only        → text-and-copy-editor (haiku)
- UI polish (CSS/responsive)   → visual-polish (sonnet, effort low)
- Normal frontend impl         → main session (sonnet)
- Planning a big/risky change  → opusplan, or architecture-auditor (opus) first

## Never use Opus for: typos.
'

# 1 — the real production shape: table names five, only two vendored
p="$(mkproj half CLAUDE.local.md)"; printf '%s' "$TABLE_BOLD" > "$p/CLAUDE.local.md"
addagent "$p" complex-implementer; addagent "$p" visual-polish
out="$(CLAUDE_CONFIG_DIR="$TMP/emptycfg" bash "$CHECK" "$p" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] \
   && grep -q 'architecture-auditor' <<< "$out" \
   && grep -q 'implementer' <<< "$out" \
   && grep -q 'text-and-copy-editor' <<< "$out"; then
  ok "half-vendored project: flags the three unvendored agents and exits non-zero"
else bad "half-vendored project: expected all three missing agents named + non-zero exit (rc=$rc)"; fi

# 2 — the same table, fully vendored: silent, zero
p="$(mkproj full CLAUDE.local.md)"; printf '%s' "$TABLE_BOLD" > "$p/CLAUDE.local.md"
for a in complex-implementer visual-polish implementer text-and-copy-editor architecture-auditor; do addagent "$p" "$a"; done
out="$(CLAUDE_CONFIG_DIR="$TMP/emptycfg" bash "$CHECK" "$p" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'every agent named in the routing table resolves' <<< "$out"; then
  ok "fully vendored project: clean, exit 0"
else bad "fully vendored project: expected clean exit 0 (rc=$rc)"; fi

# 3 — no false positives on prose, modes, tiers and built-ins
if ! grep -qE 'UNRESOLVABLE:.*(ultracode|main|built-in|opus|session)' <<< "$out" \
   && [ "$rc" -eq 0 ]; then
  ok "no false positives: 'main session', 'ultracode', 'built-in Explore' are not agents"
else bad "false positive: a mode/tier/prose token was reported as a missing agent"; fi

# 4 — the shipped template's PLAIN shape is parsed too (not just bold)
p="$(mkproj plain CLAUDE.md)"; printf '%s' "$TABLE_PLAIN" > "$p/CLAUDE.md"
addagent "$p" visual-polish
out="$(CLAUDE_CONFIG_DIR="$TMP/emptycfg" bash "$CHECK" "$p" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] \
   && grep -q 'text-and-copy-editor' <<< "$out" \
   && grep -q 'architecture-auditor' <<< "$out" \
   && ! grep -qE 'UNRESOLVABLE:.*opusplan' <<< "$out"; then
  ok "plain (unbolded) table parsed; 'opusplan' not mistaken for an agent"
else bad "plain table: expected the two missing kit agents, and opusplan excluded (rc=$rc)"; fi

# 5 — a built-in named in the table resolves without any file or plugin
p="$(mkproj builtin CLAUDE.local.md)"
printf '# model-routing policy\n\n## Routing\n- Discovery → **explore** (read-only)\n' > "$p/CLAUDE.local.md"
out="$(CLAUDE_CONFIG_DIR="$TMP/emptycfg" bash "$CHECK" "$p" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'built-in' <<< "$out"; then
  ok "built-in agents count as resolvable (no file, no plugin needed)"
else bad "built-in agent was reported as missing (rc=$rc)"; fi

# 6 — no routing table at all: silent success, never a crash
p="$(mkproj empty x)"; printf '# just a readme\n' > "$p/CLAUDE.md"
out="$(CLAUDE_CONFIG_DIR="$TMP/emptycfg" bash "$CHECK" "$p" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'no routing table found' <<< "$out"; then
  ok "project with no routing table: exits clean, says so"
else bad "no-table project should exit 0 with an explanation (rc=$rc)"; fi

# 7 — hook mode (stdin payload, not a tty) emits SessionStart additionalContext
p="$(mkproj hookmode CLAUDE.local.md)"; printf '%s' "$TABLE_BOLD" > "$p/CLAUDE.local.md"
addagent "$p" visual-polish
out="$(printf '{"cwd":"%s"}' "$p" | CLAUDE_CONFIG_DIR="$TMP/emptycfg" bash "$CHECK" </dev/stdin 2>&1)"
if grep -q 'additionalContext' <<< "$out" || grep -q 'routing table' <<< "$out"; then
  ok "hook mode emits a SessionStart warning payload"
else bad "hook mode produced no warning for a half-vendored project"; fi

# 8 — warn-once: the second identical run in hook mode stays quiet
out2="$(printf '{"cwd":"%s"}' "$p" | CLAUDE_CONFIG_DIR="$TMP/emptycfg" bash "$CHECK" </dev/stdin 2>&1)"
if [ -z "$(printf '%s' "$out2" | tr -d '[:space:]')" ]; then
  ok "warn-once: the same problem does not re-warn every session"
else bad "hook mode re-warned on an unchanged problem (would train the user to ignore it)"; fi

printf -- '----\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
