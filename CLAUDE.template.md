# model-routing policy
Use the cheapest sufficient handler. Escalate only on risk.

## Routing
- Read-only discovery (locate files/components) → let the built-in Explore subagent handle it.
  ⚠️ Inside a Workflow, Explore declares no tier of its own and runs at the DRIVER's model —
  pass `{ agentType: 'Explore', model: 'haiku' }` there, or it's the most expensive stage you have.
- Text/copy/labels only        → text-and-copy-editor (haiku)
- UI polish (CSS/responsive)    → visual-polish (sonnet, effort low)
- Normal frontend impl          → main session (sonnet)
- Moderately hard impl          → implementer (sonnet, effort high) — non-trivial logic / multi-step refactor / stateful, but not Opus-grade; escalates ONE task, session unchanged
- Hard impl (animation/algo/perf)→ complex-implementer (opus, effort high) — escalates ONE task; main session model/effort unchanged
- Planning a big/risky change   → opusplan, or architecture-auditor (opus) first
- Risky data/logic/schema/store → architecture-auditor (opus), then implement
- PR review                     → opus, or the advisor tool
- Many-agent work (audits, sweeps, migrations) → try the kit's shipped workflows first:
  `/model-routing-kit:audit` (fan-out finders → adversarial skeptics → one deciding synthesis) or
  `/model-routing-kit:migrate` (read-only plan per file → implementer applies → a different agent
  verifies). Both take `profile: frugal|balanced|frontier` to set every stage's tier at once — see
  `workflows/README.md`. Run `/model-routing-kit:probe` once in a new project to confirm routing
  actually resolves before a real run. For anything the shipped workflows don't cover, write an
  ad-hoc Workflow tool script per WORKFLOW-RUBRIC.md, opt-in. Inside a workflow every stage **MUST
  declare its tier**: the default is the SESSION's model, for all of them. Prefer `agentType:` over
  raw `{model, effort}` — it's the only form that carries the scope guard. This table does not
  apply itself.

## Escalate EFFORT before MODEL — the graduated ladder:
sonnet/low → sonnet/med → sonnet/high → sonnet/xhigh → opus/med → opus/high → opus/xhigh — automatic
escalation ENDS here. fable/high → fable/xhigh exist ABOVE the ladder as deliberate calls
(see Fable rung below), never as an automatic step. Try the cheap axis (effort) before a
bigger model; climb one rung at a time. Named rungs: implementer (sonnet/high),
complex-implementer (opus/high). Reach any in-between combo with `/run-at <model> <effort> "<task>"`
— it runs ONE task at that exact tier without changing the session model/effort.

## Never use Opus for: typos, copy edits, label/placeholder changes, file location, simple CSS spacing.

## Fable — the deliberate frontier rung (above the ladder, never automatic)
Access is plan-based, not a flip-flopping window: included at no extra cost up to 50% of the
weekly usage limit on Max plans and Premium Team/seat-based-Enterprise seats (past that, usage
credits or a fallback); pay-as-you-go via usage credits from the first token on Pro plans,
Standard seats, usage-based Enterprise, and the API. Still verify `fable` appears in /model each
session — the account's seat/plan determines this, and the allowance resets weekly — before
relying on it; fall back per the declared fallbacks below when it doesn't resolve.
Entered by a deliberate human/driver call, logged like any dispatch:
- **When it merits**: a second consecutive failure at opus (the ladder's STOP → the human
  may retry ONCE at fable instead of redesigning); one-shot-must-be-right work
  (irreversible migration plans, launch-gate audits spanning several critical invariants);
  genuinely open-ended design where solution-space search matters; the DRIVER/synthesis
  seat of a high-stakes multi-agent phase (fable plans or fans-in, cheap tiers execute —
  "fableplan").
- **Never for**: anything on the Never-use-Opus list, routine implementation, or a first
  attempt at a standard task. Fable ≈ 2× Opus per token ($10/$50) and thinks heavily by
  default — the 246k-tokens-for-a-one-line-edit measurement in DESIGN.md §2 was taken ON
  Fable. (The "~30% tokenizer overhead" that used to be stated here is **not confirmed**: the
  same system prompt cached at 16,884 tokens on fable vs 16,888 on opus, 2026-08-05. The
  always-on thinking is the real cost driver — pin `effort` and it behaves.)
- **How**: `/run-at fable high "<task>"` (one task, session unchanged); in Workflow
  scripts pass `{ model: 'fable', effort: 'xhigh' }` on at most 2–3 critical slots per
  run (deciding verdicts, final synthesis) — never on fan-outs. **Fable is the
  orchestrator's model, not a fleet model** — driver presets + fleet shape live in
  WORKFLOW-RUBRIC.md. Workflow fable slots declare their fallback up front (unavailable →
  `opus/xhigh`, never silently dropped); a missing named AGENT is still a hard STOP.

## Missing escalation agent ("Agent type not found") — STOP, never downgrade:
`enabled ≠ registered`. The plugin can be on in settings yet have ZERO agents registered (a
sibling repo sharing `CLAUDE_CONFIG_DIR` can evict the kit's marketplace). If escalating to a
named agent (complex-implementer / architecture-auditor / implementer) fails:
- Do it inline ONLY if the driver is ALREADY at or above the required tier (e.g. complex-implementer = opus/high).
- Otherwise STOP: "missing <agent>; raise with /model opus or reinstall the plugin." Wait — do not proceed.
- NEVER run the task below the tier the ladder requires. (A SessionStart self-check warns up front when this happens; reinstall at user/global scope to prevent it. A second SessionStart check, `routing-table-check.sh`, verifies specifically that every agent NAMED in this table resolves from here — it also runs standalone, in any config dir, plugin installed or not: `bash <plugin-root>/hooks/routing-table-check.sh . --verbose`. Run it by hand after editing this table or after changing `.claude/agents/`.)

## Scope guard — UI-only agents must NOT touch:
business logic, data adapters, persistence, stores, routes, schemas, fixtures, API contracts. Do not invent data.

## Measure with /usage; cap monthly spend with /usage-credits.

## Project specifics (filled by /onboard):
- Dev: <cmd>  Test: <cmd>  Lint: <cmd>  Typecheck: <cmd>  E2E: <cmd>
- Styles live in: <paths>
- Risky paths (regex): <RISKY pattern>  — source of truth is `.claude/scope-guard.conf` (`RISKY=<regex>`, plus optional per-agent `RISKY_visual_polish=` / `RISKY_text_and_copy_editor=`); this line just mirrors the base for humans.
