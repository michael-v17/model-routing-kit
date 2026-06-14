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
| Genuinely hard implementation — complex animation/canvas/WebGL/particles, tricky algorithm, perf-sensitive rendering, intricate state/concurrency | **complex-implementer** | opus, effort high |
| Risky data/logic/schema/store, or "is this change safe?" | **architecture-auditor** (inspect/plan first) | opus, effort xhigh |
| Normal frontend impl that's neither trivial nor hard | main session, or visual-polish if UI-shaped | — |

## 2. Pick the LOWEST plausible tier, then escalate only on risk signals
Escalate when the task: touches persistence/adapters/schema/stores/auth/payments, spans >5
files, mixes UI polish with data changes, or a smaller model has already failed at it.

## 3. Confirm and dispatch
- State the chosen handler and tier in one line, with the one reason it fits (e.g.
  "complex-implementer (opus/high) — particle physics a sonnet tier won't get right").
- Note explicitly: "Your session model/effort stay unchanged."
- Then delegate the task to that subagent. For read-only discovery, just let Explore handle it.
- If the task is ambiguous between two tiers, ask one quick question before dispatching.

Never route trivial edits to opus. Never route hard rendering/logic to the haiku copy tier.
