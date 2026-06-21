Manually route the task described in $ARGUMENTS to the cheapest sufficient handler, then
dispatch it. This is the explicit per-task lever: it picks a tier and delegates to a
subagent WITHOUT changing the main session's `/model` or `/effort` (so the conversation
cache is never invalidated).

If $ARGUMENTS is empty, ask the user what the task is, then proceed.

## 1. Classify the task against the ladder

| If the task is… | Route to | Tier |
|---|---|---|
| Read-only "where/how does X work" | built-in **Explore** subagent | haiku, free |
| Trivial wording/labels/typos, no layout or logic | **text-and-copy-editor** | haiku |
| UI-only polish — CSS, spacing, typography, responsive | **visual-polish** | sonnet, effort low |
| Moderately hard impl — non-trivial logic, multi-step refactor, stateful/cross-file changes that need real thought but not Opus | **implementer** | sonnet, effort high |
| Genuinely hard implementation — complex animation/canvas/WebGL/particles, tricky algorithm, perf-sensitive rendering, intricate state/concurrency | **complex-implementer** | opus, effort high |
| Risky data/logic/schema/store, or "is this change safe?" | **architecture-auditor** (inspect/plan first) | opus, effort xhigh |
| Normal frontend impl that's neither trivial nor hard | main session, or visual-polish if UI-shaped | — |

## 2. Pick the LOWEST plausible tier, then escalate only on risk signals
Escalate when the task: touches persistence/adapters/schema/stores/auth/payments, spans >5
files, mixes UI polish with data changes, or a smaller model has already failed at it.

**Escalate EFFORT before MODEL.** Effort is the cheap axis — try a higher effort on the same
model before reaching for a bigger model. The graduated ladder:

```
sonnet/low → sonnet/med → sonnet/high → opus/med → opus/high → opus/xhigh
```

Climb one rung at a time. `implementer` is the named rung at **sonnet/high**;
`complex-implementer` at **opus/high**. The in-between combos (sonnet/med, opus/med, opus/low)
aren't named agents — reach them with `/run-at <model> <effort> "<task>"`, which dispatches a
one-off subagent at that exact tier without changing your session model/effort.

## 3. Confirm and dispatch
- State the chosen handler and tier in one line, with the one reason it fits (e.g.
  "complex-implementer (opus/high) — particle physics a sonnet tier won't get right").
- Note explicitly: "Your session model/effort stay unchanged."
- Then delegate the task to that subagent. For read-only discovery, just let Explore handle it.
- If the task is ambiguous between two tiers, ask one quick question before dispatching.

## 4. If a named escalation agent is MISSING ("Agent type not found") — never degrade
`enabled ≠ registered`: the plugin can be on in settings yet have its agents unregistered (a
sibling repo sharing `CLAUDE_CONFIG_DIR` can evict the kit's marketplace — see USAGE.md). When
the agent you'd escalate to (`complex-implementer`, `architecture-auditor`, `implementer`)
doesn't exist, the rule is:

- **Build it inline in this session ONLY if the driver is already AT OR ABOVE the required tier.**
  e.g. the task maps to `complex-implementer` (opus/high) and your session is already opus/high+
  → do it inline.
- **Otherwise STOP and tell the user**: "missing `complex-implementer`; raise with `/model opus`
  (and effort) or reinstall the plugin." Then wait.
- **NEVER silently run the task on a tier BELOW what the ladder requires.** Downgrading
  opus-grade work onto a Sonnet driver is the exact failure this rule exists to prevent — and
  it's most dangerous precisely when the driver is the recommended cheap Sonnet.

Never route trivial edits to opus. Never route hard rendering/logic to the haiku copy tier.
