# model-routing-kit

Use the **cheapest sufficient model** for each Claude Code task — Haiku for trivial
copy/CSS, Sonnet for normal frontend work, Opus for risky data/architecture, Fable only when
it truly merits — and escalate only on detected risk. Ships as a Claude Code **plugin** that
adapts to each project.

> **On a Claude Code Max plan this does NOT save dollars** (flat subscription). It saves
> **usage quota** (the real weekly/5h ceiling), **latency** (Haiku ~7× faster than Fable on
> small tasks), and **context cleanliness** (delegated noise stays out of your main window).
> The per-token dollar math only applies on the pay-per-token API.

> **Fable access is plan-based, not a flip-flopping window** (per Anthropic's plan/pricing
> docs): included at no extra cost up to 50% of your weekly usage limit on **Max plans** and
> **Premium seats** (Team / seat-based Enterprise) — past that threshold it draws usage
> credits or you switch models. **Pro plans, Standard Team/Enterprise seats, usage-based
> Enterprise, and the API** pay usage credits/API rates from the first token — no included
> allowance. Still re-verify `fable` shows in `/model` each session (seat/plan can change, and
> Claude Code needs v2.1.170+ for the model picker entry) — if it's unavailable, frontier-driver
> presets fall back to sonnet/high and fable slots to opus/xhigh.
> Fable is a **deliberate rung above the ladder**, never automatic escalation —
> criteria live in CLAUDE.template.md §Fable rung. The Haiku-vs-Fable number below stays
> valid: it's the reason Fable never touches routine work.
>
> **When to orchestrate many agents at once** (Workflow tool) is its own axis, separate
> from model choice — see **WORKFLOW-RUBRIC.md**.

> 🆕 **`opus` now resolves to Claude Opus 5 (2026-07-24).** Same price as the Opus 4.8 it
> replaces — **$5/$25 per MTok** — so the top tier got stronger at zero cost delta; Anthropic
> positions it as *"close to the frontier intelligence of Fable 5 at half the price."* Two
> **API breakages** if you call Opus programmatically: thinking is now **ON by default**
> (omitting `thinking` meant *no* thinking on 4.8, and `max_tokens` caps thinking **+**
> response together → truncation risk on tightly-sized limits), and
> `thinking: {type:"disabled"}` returns **400** at `effort` `xhigh`/`max`. Also: the
> prompt-cache minimum drops to 512 tokens, and Opus 5 sits in a **separate rate-limit
> bucket** from the Opus 4.x pool.
>
> ⚠️ **What this does NOT settle.** The Fable rung, the frontier-driver preset, and the
> default-driver policy were all reasoned against **Opus 4.8**, and Opus 5 changes their
> inputs. Deliberately **not re-decided here**. Treat those sections as provisional.
> Vault: `sources/articles/claude-opus-5.md`.
>
> *Corrected 2026-08-05:* this used to say the blocker was "the Ticket 4 routing ledger, still
> unshipped". The ledger shipped — and **has never written a line** (Ticket 13). Routing turned out
> to be measurable anyway, from a workflow run's own transcript, so: Fable **resolves for real**
> inside a workflow (`claude-fable-5`, `effort: xhigh` honored). The rung is no longer blocked on
> *availability*; it stays provisional on **capability per dollar vs Opus 5**, which was always the
> actual question. See `BACKLOG.md` T10/T13/T14 and the vault's `experiments/workflow-routing/`.

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
   (no built-in equivalent). Validated, 18/18 tests.
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
Opus 5 $5/$25 (unchanged from the Opus 4.8 it replaces), Fable $10/$50. *(The "+~30% more tokens
from Fable's tokenizer" that used to be stated here is **not confirmed** — the same system prompt
cached at 16,884 tokens on fable vs 16,888 on opus, 2026-08-05. Narrow evidence, but direct: the
15× above comes from always-on thinking, not from tokenization.)*

---

## Install

```
/plugin marketplace add michael-v17/model-routing-kit
/plugin install model-routing-kit@model-routing-kit
```

Then run `/onboard` in a project to write a project-specific routing block + scope-guard
pattern into its `CLAUDE.md`. Day-to-day reference: **[`USAGE.md`](./USAGE.md)** (the ladder,
which agent for what, and "I want a harder task — which one?").

Verify the install locally before trusting it:

```
bash hooks/scope-guard.test.sh    # scope-guard behavior — 18/18
bash hooks/install-smoke.test.sh  # manifests, hook wiring, agent frontmatter — 22/22
```

## What's in the box

Full blueprint — paste-ready subagents, the scope-guard hook, plugin structure, the
`/onboard` command, and the CLAUDE.md routing template — is in **[`DESIGN.md`](./DESIGN.md)**.

Ships now: `text-and-copy-editor` (haiku) + `visual-polish` (sonnet/low) +
`implementer` (sonnet/high — the middle rung between the main session and complex-implementer) +
`complex-implementer` (opus/high — escalate one hard task without touching your session
model/effort) + `architecture-auditor` (opus/xhigh, read-only) + `hooks/scope-guard.sh`
(+ test suite) + `CLAUDE.template.md` + `/onboard` + `/route` + `/run-at`. Lean on built-in
Explore, opusplan, `/effort`, and `/usage` for the rest.

```
model-routing-kit/
  .claude-plugin/plugin.json + marketplace.json
  agents/        # text-and-copy-editor, visual-polish, implementer, complex-implementer, architecture-auditor
  hooks/         # hooks.json + scope-guard.sh (+.test.sh) + session-regcheck.sh + registration-check.sh (+.test.sh)
                 # + routing-table-check.sh (+.test.sh) + agent-telemetry.sh (+.test.sh)
                 # + docs-counts.test.sh + install-smoke.test.sh
  commands/      # onboard, route, run-at
  workflows/     # audit, migrate, probe — the ladder, executable (see workflows/README.md)
  CLAUDE.template.md
```

### Workflows — the ladder inside a fan-out

The ladder governs *your* messages. It does not govern a workflow's stages unless the script says
so: *"Every agent in a workflow uses your session's model unless the script routes a stage to a
different one."* And Claude writes those scripts, so **unrouted is the default** — a driver on
opus/xhigh fans out N agents at opus/xhigh. Measured on one real 26-agent run: the 18 stages that
declared `sonnet` resolved to `claude-sonnet-5`, the 8 that declared nothing resolved to the
driver's `claude-opus-5` — **64% of 1.49M tokens moved off the driver tier by declaring it.**

`workflows/` ships that routing frozen:

| | |
|---|---|
| `/model-routing-kit:probe` | **run first, once per repo** — 5 dispatch forms, one trivial task; proves routing and the scope guard actually work in *this* session |
| `/model-routing-kit:audit` | parallel finders → K adversarial skeptics per finding → one deciding synthesis |
| `/model-routing-kit:migrate` | read-only plan per file → implementer applies → a different agent verifies the diff |

`audit` and `migrate` take `profile` (`frugal` / `balanced` / `frontier`) to swap every stage's
tier at once, and `width` to scale the fan-out; **`probe` takes no arguments** — it is a fixed
5-probe self-test. Full argument table: `workflows/README.md`. The form doing the real work is
`{ agentType: 'model-routing-kit:<role>', model, effort }` — **scope guard from the role, tier from
you**, so a read-only auditor can run at sonnet without its native opus/xhigh riding along into a
fan-out. **Status: v0, zero real runs** — run `probe` before trusting them.

---

## Prior art

- `wshobson/agents` — per-agent `model:` tiering; fork the taxonomy.
- `disler/claude-code-damage-control` — PreToolUse scope-guard patterns.
- `musistudio/claude-code-router` — **skip** (routes off-Anthropic, bypasses Max).

## Status

**MVP built and installable.** Five core agents (`text-and-copy-editor`, `visual-polish`,
`implementer`, `complex-implementer`, `architecture-auditor`), four hooks (`scope-guard.sh`
on PreToolUse — 18/18; `session-regcheck.sh` + `routing-table-check.sh` on SessionStart —
8/8 and 8/8; `agent-telemetry.sh` on PostToolUse — 7/7), `install-smoke.test.sh` 22/22,
`/onboard`, `/route`, `/run-at`, CLAUDE template, and marketplace manifest are in place.
`workflows/` (`/model-routing-kit:{audit,migrate,probe}`) shipped as v0 — zero real runs,
run `probe` first. Remaining optional Phase 2 pieces (`web-implementer`, `pr-reviewer`) are
not yet built. Verify `fable`/`opusplan` aliases resolve in your Claude Code version before
relying on defaults that depend on them.

## License

TBD (MIT recommended).
