# model-routing-kit

> A token/quota-efficiency kit for Claude Code. Routes each task to the **cheapest
> sufficient model tier** — trivial copy/CSS to Haiku, normal frontend work to Sonnet,
> risky data/architecture to Opus, Fable only when it truly merits — and escalates only
> on detected risk. Installs as a Claude Code **plugin** that adapts to each project.

**Repo name:** `model-routing-kit` (descriptive, human). Verify it's free on GitHub before
claiming. Easy to rename — find-and-replace.

**Status:** design + validated experiments. Read §1 FIRST — **most of this is already built
into Claude Code**, so the kit you actually build is small.

> ⚠️ **Fable availability (2026-06-12):** Anthropic suspended ALL access to Claude Fable 5
> and Mythos 5 for every customer (compliance; no restore date). Other models unaffected.
> While suspended, **Opus 4.8 is the top tier** — treat every "Fable tier" mention below as
> optional/unavailable and don't ship a default that depends on the `fable` alias. The
> Haiku-vs-Fable measurement (§2) still stands as an illustration of the effort lesson (the
> same overthinking happens with Opus at high effort). Re-check before relying on Fable.

---

## 0. Why this exists (and the honest framing)

Using Opus 4.8 or Fable 5 to change a button label is like moving a box with a crane.
The instinct — *use the right tool for each moment* — is sound and is exactly what
Anthropic ships model aliases, `opusplan`, `Explore`, and per-subagent `model:`/`effort:` for.

**What you actually save (on Claude Code Max, a flat subscription):** NOT dollars — you pay
a fixed monthly fee. You save:

| Lever | Why it matters on Max |
|------|------------------------|
| **Usage quota** (weekly / 5h limits) | The real ceiling of the plan. Don't burn it on trivia. |
| **Latency** | Haiku is ~7x faster than Fable on small tasks (measured below). |
| **Context cleanliness** | Delegated execution noise stays out of the main Opus window → less compaction, better long-task coherence. |

The per-token **dollar** math only applies on the pay-per-token API. Keep both framings in
the README.

---

## 1. ⚠️ What Claude Code ALREADY does — use this BEFORE building anything

Researched against `code.claude.com/docs` (2026-06). Claude Code covers ~80% of this idea
out of the box. **Reach for these first:**

| Built-in | What it does | Replaces which kit piece |
|----------|--------------|--------------------------|
| **`Explore` subagent** | Built-in, **Haiku-backed**, read-only, auto-delegated by Claude for "find/understand the code" tasks. Keeps exploration noise out of main context. | **All of `light-inspector` — don't build it.** |
| **`opusplan` alias** | Opus during plan mode → auto-switches to Sonnet for execution. Built-in hybrid routing. | Most of the Level 4–5 plan/execute split. |
| **`/effort low\|medium\|high\|xhigh\|max`** | Lowers reasoning depth (and tokens) within a model. Settable session-wide AND per-subagent/skill via frontmatter. | The "don't overthink trivial work" goal — partially. |
| **`/usage` + `/usage-credits`** | `/usage` shows session tokens/cost and attributes the last 24h/7d to subagents, skills, plugins, MCP. `/usage-credits` sets a monthly spend cap. | **All of the measurement/telemetry phase — don't build it.** |
| **Advisor tool** | Run a cheap main model (Sonnet/Haiku) and escalate to an Opus "advisor" only at hard decision points. | An alternative to subagent routing for the escalation pattern. |
| **`/model`** | Manual model switch for the session. | The fastest fix for a one-off trivial task — just `/model haiku`. |
| **Workflows** | Script-orchestrated multi-subagent runs with per-agent token tracking. | The heavy multi-phase orchestration (only if you need it). |

**What Claude Code does NOT do** (the genuine gaps the kit fills):
1. **No automatic difficulty→model routing.** It won't auto-pick Haiku for a small edit. The
   main session reasons about the request itself; `opusplan` only switches at plan/execute,
   not per-turn.
2. **No cheap Haiku tier that EDITS.** `Explore` is read-only — there's no built-in
   "Haiku changes this label" agent.
3. **No scope-guard.** Nothing stops a UI agent from editing a data adapter.
4. **No project-specific adaptation** of any of the above.

**Honest verdict:** the kit shrinks to **4 things** — a Haiku *write* tier for trivia, a
scoped `visual-polish` agent, a **scope-guard hook**, and **project onboarding**. Everything
else, lean on the built-ins (Explore, opusplan, /effort, /usage). ~80% of the benefit is
free; the kit adds the missing 20% and packages a sane default policy.

---

## 2. The measured payoff (and why adaptive-thinking confirms it)

Same trivial task (`Book now` → `Reserve now`, one line), delegated and told to make only
the edit and stop:

| Model | Tokens | Time | Tool uses |
|-------|-------:|-----:|----------:|
| **Haiku** | 16,788 | 6.4 s | 2 |
| **Fable** (default effort) | 246,588 | 43.8 s | 4 |

**~14.7x more tokens, ~7x slower** for an identical edit.

**Adaptive-thinking explains it exactly.** Per the docs: *"At the default effort level
(`high`), Claude almost always thinks. At lower effort levels, Claude may skip thinking for
simpler problems."* Fable has thinking **always on** and defaults to **high** effort, so it
reasoned heavily over a one-liner. Adaptive thinking does **not** abate cost on its own —
**lowering `effort` is the lever.** That makes `effort: low` load-bearing on the expensive
tiers (Fable/Opus/Sonnet-4.6); it's a no-op on Haiku/Sonnet-4.5 (those don't support effort,
and Haiku is already cheap).

API pricing per MTok (input/output), for the dollar framing: Haiku $1/$5, Sonnet $3/$15,
Opus 4.8 $5/$25, **Fable $10/$50** (+ ~30% more tokens from Fable's tokenizer).

---

## 3. Prior art — borrow, don't reinvent

| Project | Borrow | Verdict |
|---------|--------|---------|
| `wshobson/agents` (~37k★) | Per-agent `model:` tiering (Opus=arch, Sonnet=docs/test, Haiku=fast). | Reference impl — fork the taxonomy. |
| `disler/claude-code-damage-control` | `patterns.yaml` PreToolUse scope guard, covers Bash too. | Borrow the convention. |
| `egorfedorov/claude-context-optimizer` | Hooks-only token measurement. | **Mostly redundant now** — `/usage` covers it. |
| `musistudio/claude-code-router` (~35k★) | API proxy to other providers. | **Skip** — bypasses Max, bills per token. |

Differentiator: a small, **frontend-adaptive** plugin that adds the Haiku write-tier +
scope-guard + onboarding on top of Claude Code's built-ins.

---

## 4. Architecture (lean version)

```
User request
  → Main session (CLAUDE.md routing policy) classifies the task
    → read-only discovery?  → built-in Explore (Haiku, free)        [DON'T build]
    → trivial text/copy?    → text-and-copy-editor (haiku)          [build]
    → UI polish?            → visual-polish (sonnet, effort low)     [build]
    → normal frontend impl? → web-implementer (sonnet, effort med)  [build, optional]
    → planning a big change?→ opusplan, or architecture-auditor     [mostly built-in]
    → risky data/arch?      → architecture-auditor (opus)           [build]
    → PR review?            → pr-reviewer (opus), or advisor tool    [build, optional]
  → PreToolUse scope-guard hook blocks out-of-scope edits           [build — the real gap]
  → measure with /usage and cap with /usage-credits                 [built-in]
```

### Task ladder

| Lvl | Kind | Handler | Notes |
|----:|------|---------|-------|
| 0 | Trivial text/copy/labels | `text-and-copy-editor` (haiku) | the Haiku **write** tier — genuinely missing from Claude |
| 1 | Read-only discovery | **built-in `Explore`** (haiku) | don't build; it's automatic |
| 2 | UI polish (CSS, responsive) | `visual-polish` (sonnet, effort low) | + scope-guard |
| 3 | Normal frontend impl | `web-implementer` (sonnet, effort medium) | optional; main session can do this |
| 4 | Risky data/logic | `architecture-auditor` (opus) first, then implement | or `opusplan` |
| 5 | Architecture / migration | `architecture-auditor` (opus, effort xhigh) | or `opusplan` |
| 6 | PR review / regression | `pr-reviewer` (opus) | or the advisor tool |

**Rule:** start at the lowest plausible level; escalate on risk (touches
persistence/adapters/schema/stores/auth/payments, >5 files, tests fail unexpectedly, mixes
UI polish with data). Never put Fable on Levels 0–1; if you use Fable, pin `effort: low` for
routine work and reserve high effort for genuinely hard long-horizon tasks.

---

## 5. Plugin structure

```
model-routing-kit/
  .claude-plugin/plugin.json
  agents/
    text-and-copy-editor.md
    visual-polish.md
    web-implementer.md          # optional
    architecture-auditor.md
    pr-reviewer.md              # optional
  hooks/
    hooks.json
    scope-guard.sh
  commands/
    onboard.md
    route.md
  CLAUDE.template.md
  README.md
```

> Note: no `light-inspector` — the built-in `Explore` subagent already does Haiku-backed
> read-only discovery for free.

### `.claude-plugin/plugin.json`
```json
{
  "name": "model-routing-kit",
  "description": "Routes each task to the cheapest sufficient model tier; scope-guards UI agents away from data/logic.",
  "version": "0.1.0",
  "author": { "name": "YOUR NAME" }
}
```

---

## 6. Subagents (paste-ready)

> Frontmatter notes: Haiku agents omit `effort` (Haiku doesn't support the effort parameter
> — it's inherently cheap). Sonnet/Opus agents carry `effort`. In plugin form, agent-level
> `hooks`/`mcpServers`/`permissionMode` are ignored — scope-guard lives in `hooks/hooks.json`,
> and Playwright/MCP is enabled at project level.

### `agents/text-and-copy-editor.md`
```markdown
---
name: text-and-copy-editor
description: Use proactively for trivial wording-only edits — visible text, labels, headings, placeholders, aria-labels, button text, empty-state copy, translation strings, typo fixes. Use only when the change needs NO layout, styling, logic, data, state, routes, schemas, or API changes.
model: haiku
tools: Read, Edit, Grep, Glob
---
You are a low-cost wording-only editor.
- Only change user-visible text or translation/copy strings.
- Never touch layout, CSS, logic, state, data, routes, imports/exports, schemas, fixtures, or tests.
- Search for the exact string before opening large files.
- If the text appears in multiple places, list matches before editing unless the target is obvious.
- If the task is not wording-only, stop and recommend escalating to visual-polish or architecture-auditor.
```

### `agents/visual-polish.md`
```markdown
---
name: visual-polish
description: Use for UI-only frontend polish — CSS, spacing, typography, responsive layout, cards, buttons, modals, visual hierarchy, screenshot matching, Playwright visual verification. Never modify business logic, data adapters, persistence, stores, routes, schemas, API contracts, or fixtures.
model: sonnet
effort: low
tools: Read, Edit, Bash, Grep, Glob
---
You are a UI polish specialist.
- Keep every change visual-only. Make minimal diffs.
- Never touch data, persistence, stores, adapters, routes, schemas, fixtures, or API contracts.
- Use screenshots/Playwright only for the requested screen or flow; do not crawl the app or dump full DOM/accessibility trees.
- If a requested visual fix requires logic/data changes, stop and escalate.
- Report changed files and confirm no data/logic files were touched.
```

### `agents/web-implementer.md` (optional — the main session can often do this)
```markdown
---
name: web-implementer
description: Use for normal frontend/mobile implementation — components, local state, forms, UI behavior, routing glue, simple validation, moderate logic. Do not perform large refactors, persistence rewrites, schema changes, or data-adapter changes without architecture review.
model: sonnet
effort: medium
tools: Read, Edit, Bash, Grep, Glob
---
You are a careful frontend/mobile implementation agent.
- Keep diffs focused; reuse existing patterns; avoid new architecture unless asked.
- Before editing, identify the expected files. After editing, run the smallest useful verification.
- Do not modify persistence, adapters, schemas, or import/export flows unless explicitly scoped.
Escalate to architecture-auditor when: >5 files change; the task touches persistence,
data adapters, schemas, API contracts, stores, auth, payments, or cross-project mappings;
or tests fail for reasons unrelated to the change.
```

### `agents/architecture-auditor.md`
```markdown
---
name: architecture-auditor
description: Use for risky work — data adapters, persistence, import/export, scenarios, routing, stores, schemas, API contracts, cross-file logic, regressions, migrations. Use BEFORE large implementation and before merge. Inspect and plan; do not implement unless explicitly asked.
model: opus
effort: xhigh
tools: Read, Grep, Glob, Bash
---
You are a conservative architecture and regression auditor. Your job is to prevent expensive mistakes.
- Prefer evidence from code over assumptions; separate facts from assumptions.
- Identify risks, dependencies, affected files, and regression points.
- Flag fake/template data vs real data, and UI surfaces powered by real vs demo content.
- Do not make changes unless explicitly asked.
Output: 1) Summary  2) Files inspected  3) Risk level  4) Findings  5) Recommended next action  6) Verification checklist.
```

### `agents/pr-reviewer.md` (optional — or use the advisor tool / built-in /review)
```markdown
---
name: pr-reviewer
description: Use for final review before commit or merge — check the diff for scope creep, unintended logic changes, data correctness, fake data presented as real, regression risk, build/test/console failures, and whether the implementation matches the request. Do not edit unless explicitly asked.
model: opus
effort: high
tools: Read, Grep, Glob, Bash
---
You are a strict PR reviewer. Review scope correctness, unintended logic changes, data
correctness, fake/template data shown as real, regression risk, build/test/console risks,
naming consistency, and mobile/responsive risks for UI work.
Return findings by severity: Blocker / High / Medium / Low / Nice-to-have.
```

> **Fable tier (optional):** if you add a Fable agent for hard long-horizon work, ALWAYS set
> `effort:` explicitly. Never expose Fable to Levels 0–1. The measurement in §2 is why.

---

## 7. Scope-guard hook (the real gap — validated, 7/7 tests)

### `hooks/hooks.json`
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit|Bash",
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/scope-guard.sh" }
        ]
      }
    ]
  }
}
```

### `hooks/scope-guard.sh`
```bash
#!/usr/bin/env bash
# PreToolUse scope-guard. If the ACTIVE subagent is UI-only (visual-polish /
# text-and-copy-editor) and the tool would touch a RISKY path, deny and ask it to escalate.
# Reads a hook payload on stdin; emits a deny decision as JSON. Exit 0 = allow.
set -euo pipefail
payload="$(cat)"

if command -v jq >/dev/null 2>&1; then
  agent_type="$(printf '%s' "$payload" | jq -r '.agent_type // "main"')"
  file_path="$(printf '%s' "$payload"  | jq -r '.tool_input.file_path // ""')"
  command_str="$(printf '%s' "$payload" | jq -r '.tool_input.command // ""')"
else
  agent_type="$(printf '%s' "$payload" | grep -o '"agent_type"[^,]*' | sed 's/.*: *"//; s/".*//' || echo main)"
  file_path="$(printf '%s' "$payload"  | grep -o '"file_path"[^,]*'  | sed 's/.*: *"//; s/".*//' || echo)"
  command_str="$(printf '%s' "$payload" | grep -o '"command"[^}]*'    | sed 's/.*: *"//; s/".*//' || echo)"
fi

case "$agent_type" in
  visual-polish|text-and-copy-editor) ui_only=1 ;;
  *) ui_only=0 ;;
esac

# Risky path pattern — TUNE PER PROJECT via /onboard (see §8).
RISKY='adapter|persistence|store|schema|migration|fixture|/api/|\.sql'

target="$file_path $command_str"
# Case-INSENSITIVE (catches camelCase userAdapter.ts / cartStore.ts) and covers Bash sed.
if [ "$ui_only" -eq 1 ] && printf '%s' "$target" | grep -Eiq "$RISKY"; then
  reason="scope-guard: '$agent_type' is UI-only but tried to touch a data/logic path ($target). Escalate to architecture-auditor."
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$reason"
  exit 0
fi
exit 0
```

**Why two details matter** (learned the hard way): the regex must be **case-insensitive**
(or `userAdapter.ts` / `cartStore.ts` slip through) and must cover **Bash** (an agent can
edit via `sed` to dodge an Edit-only guard).

---

## 8. Project onboarding — how the plugin adapts (frontend-first)

Most target projects are frontend. Ship an `/onboard` command that inspects the repo and
writes a project-specific routing block + scope-guard pattern into the project's `CLAUDE.md`.

### `commands/onboard.md`
```markdown
Analyze THIS project and propose a token-efficient model-routing setup. Do NOT edit yet — return a plan.

1. Project type: detect from package.json / config — Next.js, Vite, CRA, React Native, Vue, Svelte, Astro, plain web, or full-stack.
2. UI surfaces: where do screens/pages/components live (app/, src/pages, src/components, screens/)?
3. Styles: Tailwind config? CSS modules? styled-components? sass? Where do design tokens live?
4. Business logic & data: where are data adapters, API clients, stores (redux/zustand/pinia), persistence, schemas, fixtures, hooks, services?
5. Commands: dev, build, test, lint, typecheck, e2e — read them from package.json scripts.
6. Tooling: Playwright? a frontend design plugin? MCP servers? Storybook?
7. Risky-path patterns: from (4), produce a project-specific regex for the scope-guard (RISKY=...). Frontend default: adapter|persistence|store|schema|migration|fixture|/api/|\.sql — add this project's real folder names (e.g. src/services, src/data, prisma/).
8. Routing map: which folders/globs map to text-and-copy-editor / visual-polish / web-implementer / architecture-auditor / pr-reviewer. Note which tasks should just use the built-in Explore (read-only) or opusplan (planning).
9. Output: a CLAUDE.md routing block (from CLAUDE.template.md) filled in for this project, plus the tuned RISKY pattern for scope-guard.sh. Return the plan; ask before writing.
```

**Frontend defaults the onboarder bakes in:**
- `*.css`, Tailwind classes, JSX/TSX markup, `className`/style props → **visual-polish** scope.
- `src/data`, `src/adapters`, `src/services`, `src/store(s)`, `*.schema.*`, `prisma/`,
  `src/api`, fixtures/mocks → **risky** → guarded away from UI agents.
- Playwright discipline: verify only the changed screen/flow; report only relevant console
  errors; never dump full DOM/accessibility trees.
- React Native: enable the iOS simulator MCP at project level for visual checks.

---

## 9. CLAUDE.template.md (the routing block, ~30 lines)

```markdown
# model-routing policy
Use the cheapest sufficient handler. Escalate only on risk.

## Routing
- Read-only discovery (locate files/components) → let the built-in Explore subagent handle it.
- Text/copy/labels only        → text-and-copy-editor (haiku)
- UI polish (CSS/responsive)    → visual-polish (sonnet, effort low)
- Normal frontend impl          → web-implementer (sonnet, effort medium)  [or main session]
- Planning a big/risky change   → opusplan, or architecture-auditor (opus) first
- Risky data/logic/schema/store → architecture-auditor (opus), then implement
- PR review                     → pr-reviewer (opus), or the advisor tool

## Never use Opus/Fable for: typos, copy edits, label/placeholder changes, file location, simple CSS spacing.
## If you use Fable: pin effort:low for routine work; high effort only for genuinely hard long-horizon tasks. Never on trivial edits.

## Scope guard — UI-only agents must NOT touch:
business logic, data adapters, persistence, stores, routes, schemas, fixtures, API contracts. Do not invent data.

## Measure with /usage; cap monthly spend with /usage-credits.

## Project specifics (filled by /onboard):
- Dev: <cmd>  Test: <cmd>  Lint: <cmd>  Typecheck: <cmd>  E2E: <cmd>
- Styles live in: <paths>
- Risky paths (regex): <RISKY pattern>
```

---

## 10. Measuring whether it works — use built-ins

Don't build telemetry. Use what's there:
- **`/usage`** → session tokens/cost + attribution to subagents/skills/plugins over 24h/7d.
- **`/usage-credits`** → set a monthly spend cap (Pro/Max).
- **Console** (`platform.claude.com/usage`) → authoritative usage.
- Success = trivial edits no longer hit Opus/Fable; UI polish never touches data; heavy
  changes still get a real audit; you can pick speed/cost/quality per task.

---

## 11. Build roadmap (lean)

- **Phase 1 (MVP, ~2–3h):** `text-and-copy-editor` + `visual-polish` + `architecture-auditor`
  + `hooks/scope-guard.sh` + `CLAUDE.template.md`. Lean on built-in Explore for discovery,
  opusplan for planning, `/effort low` for routine turns, `/usage` for measurement.
- **Phase 2:** `web-implementer`, `pr-reviewer`, `/onboard`, `/route`.
- **Phase 3:** per-project tuning of the RISKY pattern + routing map across your frontend repos.
- **Phase 4 (optional):** a workflow for heavy multi-phase changes (token tracking per agent).

---

## 12. Open questions / caveats

- The main session still pays routing tokens — for one-off trivia, `/model haiku` by hand
  can beat the kit. The kit wins on *frequent mixed* workloads.
- `effort:` is a no-op on Haiku/Sonnet-4.5 — only pin it on Fable/Opus/Sonnet-4.6.
- Adaptive thinking does NOT abate cost at default `high` effort — lowering effort is the lever.
- Plugin agents ignore `hooks`/`mcpServers`/`permissionMode` frontmatter — keep hooks in
  `hooks.json`, enable MCP at project level.
- Verify `fable` and `opusplan` aliases resolve in your Claude Code version before shipping
  defaults that depend on them.
- **Reality check:** Claude Code already covers ~80% of this idea (Explore, opusplan,
  /effort, /usage). Build only the missing 20% — Haiku write-tier, scoped visual-polish,
  scope-guard, onboarding — and don't reinvent the rest.

---

*Blueprint from feasibility experiments in a personal AI vault (2026-06-12): spec
verification, GitHub prior-art, a validated scope-guard hook (7/7), a Haiku-vs-Fable token
measurement (~15x), and a review of Claude Code's built-in routing/efficiency features.*
