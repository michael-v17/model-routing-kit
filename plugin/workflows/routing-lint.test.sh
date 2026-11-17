#!/usr/bin/env bash
# routing-lint — the one rule this kit exists for, mechanized.
#
# WORKFLOW-RUBRIC.md says "every agent() stage MUST declare its tier". That is prose in a
# .md file, the default runs against it, and an unrouted stage still returns a perfectly
# good answer — it just costs the driver's tier. Nothing about normal use surfaces that.
# So: check it.
#
# What this CAN prove: every agent() call site in workflows/ carries a routing declaration,
# and every PROFILES table declares model+effort for each stage.
# What this CANNOT prove: that a spread (`...C.P.find`) actually resolves to a tier at
# runtime, or that the tier asked for is the tier that answered. For that, run
# /model-routing-kit:probe and read the transcript. This lint reports which form each call
# site used so you can see for yourself, rather than printing a green tick over a guess.
#
# Opt out of a single call site with the marker: // routing-lint: intentional-unrouted
set -u
cd "$(dirname "$0")" || exit 1

pass=0; fail=0
ok()  { printf 'PASS   | %s\n' "$1"; pass=$((pass+1)); }
bad() { printf 'FAIL   | %s\n' "$1"; fail=$((fail+1)); }

command -v python3 >/dev/null 2>&1 || { echo "SKIP   | python3 not available — routing lint not run"; exit 0; }

shopt -s nullglob
files=(*.js)
[ ${#files[@]} -gt 0 ] || { bad "no workflow scripts found in workflows/"; echo; echo "0 passed, 1 failed"; exit 1; }

for f in "${files[@]}"; do
  out=$(python3 - "$f" <<'PY'
import re, sys

path = sys.argv[1]
raw = open(path).read()
problems, notes = [], []

# Blank out comments and string bodies (keeping newlines, so line numbers stay true)
# before looking for call sites — otherwise every prose mention of `agent()` in a
# comment gets reported as an unrouted stage, and a lint that cries wolf gets muted.
def blank(s):
    # strictly length-preserving: every masked char becomes a space, newlines survive
    out, i, n = list(s), 0, len(s)
    def wipe(a, b):
        for k in range(a, min(b, n)):
            if out[k] != '\n':
                out[k] = ' '
    while i < n:
        two = s[i:i + 2]
        if two == '//':
            j = s.find('\n', i); j = n if j < 0 else j
            wipe(i, j); i = j
        elif two == '/*':
            j = s.find('*/', i + 2); j = n if j < 0 else j + 2
            wipe(i, j); i = j
        elif s[i] in '"\'`':
            q, j = s[i], i + 1
            while j < n:
                if s[j] == '\\':
                    j += 2; continue
                if s[j] == q:
                    break
                j += 1
            wipe(i + 1, j); i = min(j + 1, n)
        else:
            i += 1
    return ''.join(out)

src = blank(raw)
lines_raw = raw.split('\n')

# --- meta shape -------------------------------------------------------------
m = re.search(r'export\s+const\s+meta\s*=\s*\{', raw)
if not m:
    problems.append("no `export const meta = {` — the runtime needs it to name the slash command")
else:
    head = raw[m.start():m.start() + 1200]
    for field in ('name', 'description'):
        if not re.search(r'\b%s\s*:' % field, head):
            problems.append("meta is missing `%s`" % field)
    nm = re.search(r"\bname\s*:\s*'([^']+)'", head)
    if nm:
        notes.append("slash command: /model-routing-kit:%s" % nm.group(1))

# --- every agent() call site declares a tier --------------------------------
# Walk from each `agent(` to its matching close paren, respecting nesting and strings.
def call_span(s, start):
    i, depth, quote = start, 0, None
    while i < len(s):
        c = s[i]
        if quote:
            if c == '\\':
                i += 2; continue
            if c == quote:
                quote = None
        elif c in '"\'`':
            quote = c
        elif c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0:
                return s[start:i + 1]
        i += 1
    return s[start:]

forms = {'explicit': 0, 'spread': 0, 'exempt': 0}
for mm in re.finditer(r'(?<![\w.])agent\s*\(', src):
    body = call_span(src, mm.end() - 1)
    line = src[:mm.start()].count('\n') + 1
    # the opt-out marker lives in a comment, so look for it in the ORIGINAL text
    ctx = '\n'.join(lines_raw[max(0, line - 7):line + 2])
    if 'routing-lint: intentional-unrouted' in ctx:
        forms['exempt'] += 1
        notes.append("line %d: UNROUTED on purpose (marker present) — runs at the driver's tier" % line)
    elif re.search(r'\bmodel\s*:', body) or re.search(r'\bagentType\s*:', body):
        forms['explicit'] += 1
    elif re.search(r'\.\.\.\s*[A-Za-z_$][\w$.]*', body):
        forms['spread'] += 1
        sp = re.search(r'\.\.\.\s*([A-Za-z_$][\w$.]*)', body).group(1)
        notes.append("line %d: routed via spread `...%s` — lint trusts it; probe proves it" % (line, sp))
    else:
        problems.append("line %d: agent() call declares no model, no agentType, and no opt-out marker "
                        "— this stage will run at the SESSION's tier" % line)

if sum(forms.values()) == 0:
    problems.append("no agent() calls found — is this a workflow?")

# --- profile tables carry a tier per stage ----------------------------------
pm = re.search(r'const\s+PROFILES\s*=\s*\{', raw)
if pm:
    tbl = raw[pm.end() - 1:]
    depth, i = 0, 0
    while i < len(tbl):
        if tbl[i] == '{': depth += 1
        elif tbl[i] == '}':
            depth -= 1
            if depth == 0:
                tbl = tbl[:i + 1]; break
        i += 1
    for prof in re.finditer(r'^\s{2}(\w+)\s*:\s*\{', tbl, re.M):
        name = prof.group(1)
        seg = tbl[prof.end():tbl.find('\n  },', prof.end()) + 1]
        for stage in re.finditer(r'(\w+)\s*:\s*\{([^}]*)\}', seg):
            sname, sbody = stage.group(1), stage.group(2)
            if not (re.search(r'\bmodel\s*:', sbody) or re.search(r'\bagentType\s*:', sbody)):
                problems.append("PROFILES.%s.%s declares neither model nor agentType" % (name, sname))
            elif 'model' in sbody and 'haiku' not in sbody and not re.search(r'\beffort\s*:', sbody):
                notes.append("PROFILES.%s.%s sets model without effort — the model's default effort applies" % (name, sname))

print("FORMS explicit=%d spread=%d exempt=%d" % (forms['explicit'], forms['spread'], forms['exempt']))
for n in notes:    print("NOTE " + n)
for p in problems: print("PROB " + p)
PY
)
  probs=$(printf '%s\n' "$out" | grep '^PROB ' | sed 's/^PROB //')
  formline=$(printf '%s\n' "$out" | grep '^FORMS ' | sed 's/^FORMS //')

  if [ -z "$probs" ]; then
    ok "$f — every agent() stage declares a tier ($formline)"
  else
    while IFS= read -r p; do [ -n "$p" ] && bad "$f — $p"; done <<< "$probs"
  fi
  printf '%s\n' "$out" | grep '^NOTE ' | sed "s/^NOTE /       ~ $f: /"
done

echo
echo "$pass passed, $fail failed"
echo "note: a green run proves every call site DECLARES a tier. It does not prove the tier"
echo "      that answered. Run /model-routing-kit:probe, then compare agent-<id>.meta.json"
echo "      (asked) against .message.model in agent-<id>.jsonl (answered)."
[ "$fail" -eq 0 ]
