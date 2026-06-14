# model-routing-kit

Use the **cheapest sufficient model** for each Claude Code task — Haiku for trivial
copy/CSS, Sonnet for normal frontend work, Opus for risky data/architecture, Fable only when
it truly merits — and escalate only on detected risk. Ships as a Claude Code **plugin** that
adapts to each project.

> **On a Claude Code Max plan this does NOT save dollars** (flat subscription). It saves
> **usage quota** (the real weekly/5h ceiling), **latency** (Haiku ~7× faster than Fable on
> small tasks), and **context cleanliness** (delegated noise stays out of your main window).
> The per-token dollar math only applies on the pay-per-token API.

> ⚠️ **2026-06-12:** Anthropic suspended all access to **Fable 5 / Mythos 5** (compliance, no
> restore date; other models unaffected). While suspended, **Opus 4.8 is the top tier** —
> treat Fable mentions here as optional/unavailable. The Haiku-vs-Fable number below stays
> valid as an illustration (Opus at high effort overthinks the same way).

---

## ⚡ Try this FIRST — zero code, today

Claude Code already covers ~80% of this idea out of the box. Live with these for a week
before building anything:

| Do this | What it gives you |
|---------|-------------------|
| `/model haiku` for a trivial session; `/model opusplan` for a feature (Opus plans → Sonnet executes) | Right-sized model per session. |
| `/effort low` for routine work | At default `high` effort the model almost always thinks; `low` skips thinking on simple tasks. **This is the real cost lever** — adaptive thinking alone doesn't cut cost. |
| Just ask "where does X live?" | Claude auto-delegates to the built-in **Explore** subagent (Haiku, read-only) — free, fast discovery that stays out of your main context. |
| `/usage` | Session tokens/cost + attribution to subagents/skills/plugins (24h/7d). Use it to *prove* the routing saves quota. |
| `/usage-credits` | Set a monthly spend cap (Pro/Max). |

`/model` and `/effort` are confirmed working. Verify `/usage`, `/usage-credits`, and the
`opusplan` option exist in your version via `/help` and the `/model` menu.

**If after a week, switching models by hand gets tedious → then build the plugin below.**

---

## What the plugin adds (the missing 20%)

Claude Code does **not** ship these, so the kit provides them:

1. **A Haiku tier that *edits*** — `text-and-copy-editor` for trivial copy/label changes
   (the built-in `Explore` is read-only).
2. **A scoped `visual-polish` agent** — UI-only changes, never touches data/logic.
3. **A scope-guard hook** — blocks a UI agent from editing data adapters/stores/schemas
   (no built-in equivalent). Validated, 7/7 tests.
4. **Project onboarding** (`/onboard`) — detects your stack (frontend-first) and writes a
   project-specific routing map + scope-guard pattern.

Everything else (discovery, planning, measurement) leans on the built-ins above.

---

## Why it matters (measured)

Identical one-line edit (`Book now` → `Reserve now`), delegated and told to stop after:

| Model | Tokens | Time |
|-------|-------:|-----:|
| Haiku | 16,788 | 6.4 s |
| Fable (default effort) | 246,588 | 43.8 s |

**~15× more tokens, ~7× slower** — because Fable has always-on thinking at default `high`
effort. Pinning `effort: low` is mandatory on the expensive tiers; it's a no-op on Haiku.

API pricing per MTok (in/out), for the dollar framing: Haiku $1/$5, Sonnet $3/$15,
Opus 4.8 $5/$25, Fable $10/$50 (+ ~30% more tokens from Fable's tokenizer).

---

## Install

```
/plugin marketplace add michael-v17/model-routing-kit
/plugin install model-routing-kit@model-routing-kit
```

Then run `/onboard` in a project to write a project-specific routing block + scope-guard
pattern into its `CLAUDE.md`.

Verify the install locally before trusting it:

```
bash hooks/scope-guard.test.sh    # scope-guard behavior — 7/7
bash hooks/install-smoke.test.sh  # manifests, hook wiring, agent frontmatter — 8/8
```

## What's in the box

Full blueprint — paste-ready subagents, the scope-guard hook, plugin structure, the
`/onboard` command, and the CLAUDE.md routing template — is in **[`DESIGN.md`](./DESIGN.md)**.

The MVP ships now: `text-and-copy-editor` + `visual-polish` + `architecture-auditor` +
`hooks/scope-guard.sh` (+ test suite) + `CLAUDE.template.md` + `/onboard`. Lean on built-in
Explore, opusplan, `/effort`, and `/usage` for the rest.

```
model-routing-kit/
  .claude-plugin/plugin.json + marketplace.json
  agents/        # text-and-copy-editor, visual-polish, architecture-auditor (+ optional web-implementer, pr-reviewer)
  hooks/         # hooks.json + scope-guard.sh + scope-guard.test.sh + install-smoke.test.sh
  commands/      # onboard (+ optional route)
  CLAUDE.template.md
```

---

## Prior art

- `wshobson/agents` — per-agent `model:` tiering; fork the taxonomy.
- `disler/claude-code-damage-control` — PreToolUse scope-guard patterns.
- `musistudio/claude-code-router` — **skip** (routes off-Anthropic, bypasses Max).

## Status

**MVP built and installable.** Core agents, scope-guard hook (7/7 behavior tests, 8/8 install
smoke tests), `/onboard`, CLAUDE template, and marketplace manifest are in place. Optional
Phase 2 pieces (`web-implementer`, `pr-reviewer`, `/route`) are not yet built. Verify
`fable`/`opusplan` aliases resolve in your Claude Code version before relying on defaults
that depend on them.

## License

TBD (MIT recommended).
