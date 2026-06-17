# Developing model-routing-kit (dev context for Claude)

This file orients a fresh session working **on the kit itself**. It is NOT installed into
target projects — that's `CLAUDE.template.md`. Read this first; it's the source of truth for
state and conventions here.

## What this repo is

A Claude Code **plugin** that routes each task to the cheapest sufficient model tier and
scope-guards UI agents away from data/logic. **Status: MVP built and installable** (v0.1.0).
Don't trust notes that say "plugin not yet built" — those are stale vault notes (see below).

## Two homes — don't confuse them

- **This repo** (`~/Desktop/Projects/Personal/tooling/model-routing-kit/`) = the **implementation**.
  Its own git repo. Code, agents, hooks, tests ship from here.
- **The vault** (`~/Desktop/Projects/Personal/AI/experiments/agent-routing-kit/`) = the
  **notes/design/findings/learnings** side. `learnings.md` there records the dogfood results.
  Its README is **stale** (says "plugin not built"). When you change behavior here, reconcile
  the vault notes so the two don't drift.

## The one decision that matters most

From the tecnologiasvm dogfood: **90% of the bill was the Opus driver session, not the
subagents.** Routing leaves to Haiku/Sonnet is necessary but not sufficient. The dominant
lever is **running the driver session on Sonnet**, escalating to Opus only per-task via
subagents (`complex-implementer` / `architecture-auditor`). Keep this front-of-mind when
editing routing guidance — leaf savings are a rounding error next to the driver model.

## File map

| Path | What |
|------|------|
| `.claude-plugin/plugin.json` + `marketplace.json` | plugin manifest + marketplace entry |
| `agents/text-and-copy-editor.md` | Haiku tier that *edits* — trivial copy/strings only |
| `agents/visual-polish.md` | Sonnet/low — UI-only (CSS/markup), never data/logic |
| `agents/implementer.md` | Sonnet/high — intermediate rung; moderately hard impl (non-trivial logic/refactor/state) w/o changing session model. NOT scope-guarded (not a UI-only agent) |
| `agents/complex-implementer.md` | Opus/high — escalate one hard task w/o changing session model |
| `agents/architecture-auditor.md` | Opus/xhigh, read-only — inspect/plan risky work |
| `hooks/scope-guard.sh` | PreToolUse hook: blocks UI agents from editing `RISKY` paths. RISKY is read from `.claude/scope-guard.conf` (`key=value`) per-agent (Ticket 2: `RISKY_<agent>` > `RISKY` > built-in default; built-in defaults differ per agent — copy editor also blocked from stylesheets) |
| `hooks/scope-guard.test.sh` | behavior tests (16/16) |
| `hooks/install-smoke.test.sh` | manifest/wiring/frontmatter tests (10/10) |
| `commands/onboard.md` | `/onboard` — writes a project-specific routing block + RISKY pattern |
| `commands/route.md` | `/route` — per-task escalation helper |
| `commands/run-at.md` | `/run-at <model> <effort> "<task>"` — manual per-task tier knob; dispatches a one-off subagent at the exact tier without changing session `/model`/`/effort`; logs `source:"manual"` to `.claude/routing-log.jsonl` (Ticket 5A) |
| `CLAUDE.template.md` | what `/onboard` installs into a target project (≠ this file) |
| `DESIGN.md` | full blueprint |
| `BACKLOG.md` | **pending work lives here** — read before starting a change |

## Conventions

- **`BACKLOG.md` is the to-do source of truth.** 3 dogfood tickets open: RISKY-from-config,
  per-agent scope, copy-editor over-rewrite guard. Add/close tickets there, not in scattered notes.
- **Verify before trusting a change:** `bash hooks/scope-guard.test.sh` (16/16) and
  `bash hooks/install-smoke.test.sh` (10/10) must pass.
- **RISKY is configurable per project AND per agent** via `.claude/scope-guard.conf`
  (`key=value`). Resolution for a given agent: `RISKY_<agent>` (hyphens→underscores, e.g.
  `RISKY_visual_polish`) > base `RISKY` > built-in default. A per-agent key REPLACES the base
  for that agent (it does not merge). Built-in defaults are differentiated (Ticket 2): both UI
  agents are blocked from data/logic, but `text-and-copy-editor` is ALSO blocked from
  stylesheets (restyling is visual-polish's job). `/onboard` writes the conf — it must never
  fork `scope-guard.sh`.
- **Fable is suspended** (since 2026-06-12, no restore date) — Opus 4.8 is top tier meanwhile.
  Verify `fable`/`opusplan` aliases resolve before relying on defaults that depend on them.
- The hook fires on `Edit|Write|MultiEdit|Bash` via `${CLAUDE_PLUGIN_ROOT}/hooks/scope-guard.sh`.
