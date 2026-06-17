# model-routing policy
Use the cheapest sufficient handler. Escalate only on risk.

## Routing
- Read-only discovery (locate files/components) → let the built-in Explore subagent handle it.
- Text/copy/labels only        → text-and-copy-editor (haiku)
- UI polish (CSS/responsive)    → visual-polish (sonnet, effort low)
- Normal frontend impl          → main session, or add a web-implementer (sonnet, effort medium)
- Hard impl (animation/algo/perf)→ complex-implementer (opus, effort high) — escalates ONE task; main session model/effort unchanged
- Planning a big/risky change   → opusplan, or architecture-auditor (opus) first
- Risky data/logic/schema/store → architecture-auditor (opus), then implement
- PR review                     → opus, or the advisor tool

## Never use Opus for: typos, copy edits, label/placeholder changes, file location, simple CSS spacing.
## Fable: currently suspended (2026-06-12) — Opus 4.8 is the top tier. If restored, pin effort:low for routine work; never on trivial edits.

## Scope guard — UI-only agents must NOT touch:
business logic, data adapters, persistence, stores, routes, schemas, fixtures, API contracts. Do not invent data.

## Measure with /usage; cap monthly spend with /usage-credits.

## Project specifics (filled by /onboard):
- Dev: <cmd>  Test: <cmd>  Lint: <cmd>  Typecheck: <cmd>  E2E: <cmd>
- Styles live in: <paths>
- Risky paths (regex): <RISKY pattern>  — source of truth is `.claude/scope-guard.conf` (`RISKY=<regex>`, plus optional per-agent `RISKY_visual_polish=` / `RISKY_text_and_copy_editor=`); this line just mirrors the base for humans.
