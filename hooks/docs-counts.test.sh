#!/usr/bin/env bash
# docs-counts — the test-count claims in the docs must equal what the suites actually print.
#
# WHY THIS EXISTS (it is not hypothetical):
#   On 2026-08-07 an audit found the scope-guard suite cited as 7/7 in README.md and DESIGN.md
#   and as 16/16 in CLAUDE.md, while it actually printed 18. install-smoke was cited as 8/8 and
#   14/14; it printed 19. Four wrong numbers across three files, all written in good faith, none
#   caught by any test — because a number in prose is a claim nobody re-runs.
#
#   Root cause, and it is mechanical: scope-guard.test.sh was the only suite of six without a
#   tally line, so its count had to be eyeballed. That is fixed; this closes the loop.
#
# WHAT IT PROVES: every doc line that names a suite AND carries an N/M or "N passed" agrees with
# that suite's current output.
# WHAT IT DOES NOT PROVE: prose that describes a suite without naming it in a way this can match.
# Those are listed as UNCHECKED rather than passed silently — a guard that hides its blind spot
# is worse than one that has none.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

pass=0; fail=0
ok()  { printf 'PASS   | %s\n' "$1"; pass=$((pass+1)); }
bad() { printf 'FAIL   | %s\n' "$1"; fail=$((fail+1)); }

# suite path : stem used to find mentions in prose
SUITES="
hooks/scope-guard.test.sh|scope-guard
hooks/registration-check.test.sh|registration-check
hooks/agent-telemetry.test.sh|agent-telemetry
hooks/routing-table-check.test.sh|routing-table-check
workflows/routing-lint.test.sh|routing-lint
hooks/install-smoke.test.sh|install-smoke
"

unchecked=0

while IFS='|' read -r suite stem; do
  [ -n "${suite:-}" ] || continue
  [ -f "$suite" ] || { bad "$suite does not exist but is referenced by this check"; continue; }

  # RK_SKIP_DOCS_COUNTS breaks the recursion when we run install-smoke, which runs us.
  n="$(RK_SKIP_DOCS_COUNTS=1 bash "$suite" 2>/dev/null | sed -n 's/^\([0-9][0-9]*\) passed.*/\1/p' | tail -n1)"
  if [ -z "$n" ]; then
    bad "$suite prints no 'N passed' tally — its count cannot be verified, so any doc citing it will drift"
    continue
  fi

  # Doc lines that name this suite AND state a ratio or a passed-count.
  #
  # Two calibrations, both learned the hard way on the first run of this file:
  #
  # 1. Take the ratio that FOLLOWS this stem on the line, not the first ratio on the line.
  #    Real docs list several suites per line — "registration-check.test.sh (8/8),
  #    agent-telemetry.test.sh (7/7)" — and taking the first number reports agent-telemetry
  #    as claiming 8. That is a lie about a correct line, which is the fastest way to get a
  #    guard muted.
  # 2. BACKLOG.md is a DATED LEDGER. "scope-guard intacto 16/16" was true the day it was
  #    written; a changelog is not required to track the present. Reported as INFO, never FAIL.
  # Prose writes suite names both ways — "install-smoke" and "install smoke". Matching only the
  # hyphen let `README.md:186` ("19/19 install smoke tests") sail past while the same line matched
  # a DIFFERENT suite's ratio and reported green. Accept either separator.
  stem_rx="$(printf '%s' "$stem" | sed 's/-/[- ]/g')"
  bad_lines=""; stale_log=""
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    f="${hit%%:*}"; rest="${hit#*:}"; ln="${rest%%:*}"; text="${rest#*:}"
    after="$(printf '%s' "$text" | sed -E "s/.*$stem_rx//")"
    # A test count is written N/N — "18/18", "7/7". A ratio with different halves is something
    # else entirely: "(Tickets 6/7)" in CLAUDE.md matched on the first run of this check and got
    # reported as a wrong test count. Requiring both halves to match kills that class outright,
    # at the cost of never noticing a doc that cites a FAILING suite — which no doc should.
    claimed="$(printf '%s' "$after" \
      | grep -oE '[0-9]+/[0-9]+|[0-9]+ passed' \
      | awk -F'[/ ]' '$1==$2 || $2=="passed" {print $1; exit}')"
    [ -n "$claimed" ] || continue
    [ "$claimed" = "$n" ] && continue
    case "$f" in
      *BACKLOG.md) stale_log="$stale_log\n       $f:$ln says $claimed (dated entry — informational)" ;;
      *)           bad_lines="$bad_lines\n       $f:$ln claims $claimed, actual $n" ;;
    esac
  done <<EOF
$(grep -rnE "$stem_rx" --include='*.md' . 2>/dev/null | grep -E '[0-9]+/[0-9]+|[0-9]+ passed' | grep -v '^\./\.git/')
EOF
  [ -n "$stale_log" ] && printf 'INFO   | %s: dated ledger entries not matching current count:%b\n' "$stem" "$stale_log"

  if [ -n "$bad_lines" ]; then
    bad "$suite → prints $n, but the docs disagree:$(printf '%b' "$bad_lines")"
  else
    ok "$suite → $n passed; every doc line naming it agrees"
  fi
done <<EOF
$(printf '%s\n' "$SUITES" | sed '/^$/d')
EOF

# Blind spot, stated out loud: prose that describes a suite without a matchable stem.
loose="$(grep -rnE '[0-9]+/[0-9]+ tests?|Validated, [0-9]+' --include='*.md' . 2>/dev/null \
  | grep -v '^\./\.git/' \
  | grep -vE 'scope-guard|registration-check|agent-telemetry|routing-table-check|routing-lint|install-smoke' || true)"
if [ -n "$loose" ]; then
  unchecked=$(printf '%s\n' "$loose" | wc -l | tr -d ' ')
  printf 'UNCHECKED (%s) | doc lines with a test-count shape that name no suite — verify by hand:\n' "$unchecked"
  printf '%s\n' "$loose" | sed 's/^/       /'
fi

printf -- '----\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
