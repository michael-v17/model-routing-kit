# model-routing policy
Use the cheapest sufficient handler. Escalate only on risk.

## Routing
- Read-only discovery (locate files/components) → let the built-in Explore subagent handle it.
- Text/copy/labels only        → text-and-copy-editor (haiku)
- UI polish (CSS/responsive)    → visual-polish (sonnet, effort low)
- Normal frontend impl          → main session (sonnet)
- Moderately hard impl          → implementer (sonnet, effort high) — non-trivial logic / multi-step refactor / stateful, but not Opus-grade; escalates ONE task, session unchanged
- Hard impl (animation/algo/perf)→ complex-implementer (opus, effort high) — escalates ONE task; main session model/effort unchanged
- Planning a big/risky change   → opusplan, or architecture-auditor (opus) first
- Risky data/logic/schema/store → architecture-auditor (opus), then implement
- PR review                     → opus, or the advisor tool

## Escalate EFFORT before MODEL — the graduated ladder:
sonnet/low → sonnet/med → sonnet/high → opus/med → opus/high → opus/xhigh. Try the cheap axis
(effort) before a bigger model; climb one rung at a time. Named rungs: implementer (sonnet/high),
complex-implementer (opus/high). Reach any in-between combo with `/run-at <model> <effort> "<task>"`
— it runs ONE task at that exact tier without changing the session model/effort.

## Never use Opus for: typos, copy edits, label/placeholder changes, file location, simple CSS spacing.
## Fable: currently suspended (2026-06-12) — Opus 4.8 is the top tier. If restored, pin effort:low for routine work; never on trivial edits.

## Missing escalation agent ("Agent type not found") — STOP, never downgrade:
`enabled ≠ registered`. The plugin can be on in settings yet have ZERO agents registered (a
sibling repo sharing `CLAUDE_CONFIG_DIR` can evict the kit's marketplace). If escalating to a
named agent (complex-implementer / architecture-auditor / implementer) fails:
- Do it inline ONLY if the driver is ALREADY at or above the required tier (e.g. complex-implementer = opus/high).
- Otherwise STOP: "missing <agent>; raise with /model opus or reinstall the plugin." Wait — do not proceed.
- NEVER run the task below the tier the ladder requires. (A SessionStart self-check warns up front when this happens; reinstall at user/global scope to prevent it.)

## Scope guard — UI-only agents must NOT touch:
business logic, data adapters, persistence, stores, routes, schemas, fixtures, API contracts. Do not invent data.

## Measure with /usage; cap monthly spend with /usage-credits.

## Project specifics (filled by /onboard):
- Dev: <cmd>  Test: <cmd>  Lint: <cmd>  Typecheck: <cmd>  E2E: <cmd>
- Styles live in: <paths>
- Risky paths (regex): <RISKY pattern>  — source of truth is `.claude/scope-guard.conf` (`RISKY=<regex>`, plus optional per-agent `RISKY_visual_polish=` / `RISKY_text_and_copy_editor=`); this line just mirrors the base for humans.
