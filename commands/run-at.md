Run the task at an EXACT tier you choose, as a one-off subagent — without changing the
session's `/model` or `/effort` (so the conversation cache stays intact). This is the manual
counterpart to `/route`: `/route` picks the tier for you; `/run-at` lets you dictate it.

Usage: `/run-at <model> <effort> "<task>"`  (e.g. `/run-at sonnet high "refactor the cart reducer"`)

`$ARGUMENTS` holds the whole line. Parse the FIRST one or two tokens as the tier, the rest as
the task. If the tier or task is missing/ambiguous, ask once, then proceed.

## 1. Parse the tier (model + effort)

Two leading tokens, **positional**: first = model, second = effort. Each accepts a one-letter
shorthand, a full word, or a joined two-char form (`oh`, `sm`). The letter `h` is disambiguated
by position — in the model slot it's haiku, in the effort slot it's high.

| Slot | Shorthand → value |
|---|---|
| **model** (1st) | `o`/`opus` → opus · `s`/`sonnet` → sonnet · `h`/`haiku` → haiku |
| **effort** (2nd) | `l`/`low` → low · `m`/`med`/`medium` → medium · `h`/`high` → high · `x`/`xhigh` → xhigh |

- `s h "…"` → sonnet / high.  `h m "…"` → haiku / medium.  `o x "…"` → opus / xhigh.
- Joined: `oh "…"` → opus / high.  `sm "…"` → sonnet / medium.  `hh "…"` → haiku / high.
  (First char = model, remaining chars = effort.)
- Note: Haiku ignores effort (no always-on thinking), so `h h`/`h l` run the same — that's fine.

If the model word isn't o/s/h or the effort isn't l/m/h/x, ask one quick question; don't guess.

## 2. Dispatch at that exact tier (session untouched)

Delegate the task to a one-off subagent pinned to the parsed **model**, instructing it to think
at the parsed **effort** level. Use the existing named agent when one already matches the tier
AND the work (e.g. opus/high hard rendering → `complex-implementer`; sonnet/high moderately
hard impl → `implementer`); otherwise dispatch a general subagent with the model override and an
effort directive. Either way:

- **Do NOT run `/model` or `/effort`.** The session's tier stays exactly where it is — only this
  one task runs elevated/lowered. State that explicitly: "Your session model/effort stay unchanged."
- Announce the dispatch in one line: the chosen model/effort and the task.
- The scope-guard still applies project-wide.

## 3. Log the manual choice (feeds /route-review, Ticket 4)

After dispatching, append ONE line to `.claude/routing-log.jsonl` in the project so a later
review can spot intuition misfires (e.g. opus/high spent on a trivial task, or a haiku retry
that should have started higher). Run:

```bash
mkdir -p "${CLAUDE_PROJECT_DIR:-.}/.claude"
printf '{"ts":"%s","source":"manual","model":"%s","effort":"%s","task":"%s"}\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "<model>" "<effort>" "<task, quotes/backslashes escaped>" \
  >> "${CLAUDE_PROJECT_DIR:-.}/.claude/routing-log.jsonl"
```

Substitute the resolved `<model>`/`<effort>` (full words) and the task text. Keep the task on one
line; escape `"` and `\` so the line stays valid JSON. This file is gitignored in onboarded projects.

Never silently downgrade or upgrade what the user asked for — run exactly the tier parsed.
