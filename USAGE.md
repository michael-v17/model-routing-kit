# Using model-routing-kit — cheat sheet

Day-to-day reference for routing tasks to the right tier. The golden rule, then the ladder,
then the exact commands.

## The one rule

**Run the driver session on Sonnet** (`/model sonnet`), and escalate *per task* — don't sit
on Opus. The first dogfood showed ~90% of the cost was the Opus driver session, not the
subagents. Cheap leaves only help if the driver itself is cheap.

```
/model sonnet     # start here for routine frontend work
```

## The ladder — task → handler → tier

| If the task is… | Use | Tier |
|---|---|---|
| "Where/how does X work?" (read-only) | built-in **Explore** (automatic) | haiku, free |
| Trivial wording / labels / typos / aria — no layout or logic | **text-and-copy-editor** | haiku |
| UI-only polish — CSS, spacing, type, responsive | **visual-polish** | sonnet, effort low |
| Normal frontend that's neither trivial nor hard | **main session** (you, on sonnet) | sonnet |
| **Moderately hard, ONE task** — non-trivial logic, multi-step refactor, stateful/cross-file changes that need thought but not Opus | **implementer** | **sonnet, effort high** |
| **Genuinely hard, ONE task** — complex animation/canvas/WebGL/particles, tricky algorithm, perf rendering, intricate state | **complex-implementer** | **opus, effort high** |
| Risky / "is this change safe?" — data, schema, stores, routing, contracts, migrations | **architecture-auditor** (inspect & plan first) | opus, effort xhigh |
| Big multi-section sweep / whole feature | **opusplan** (`/model opusplan`) | opus plans → sonnet executes |

**Rule of thumb:** pick the *lowest* plausible tier; escalate only on a real risk signal
(touches persistence/auth/payments, spans >5 files, mixes UI with data, or a smaller model
already failed at it).

**Escalate effort before model.** Effort is the cheap axis — bump it on the same model before
reaching for a bigger one. The graduated ladder, one rung at a time:

```
sonnet/low → sonnet/med → sonnet/high → opus/med → opus/high → opus/xhigh
```

Two rungs are named agents — `implementer` (sonnet/high) and `complex-implementer` (opus/high).
The in-between combos (sonnet/med, opus/med, opus/low) aren't; hit them with
`/run-at <model> <effort> "<task>"`.

## "I want to launch a harder task — which one?"

- **Hard, one-off, needs more horsepower, but I don't want to change my session** →
  **`complex-implementer`** (opus/high). It runs that single task at a high tier and your
  `/model` + `/effort` stay put (conversation cache intact).
- **Risky and I want it reviewed before touching code** → **`architecture-auditor`**
  (opus/xhigh, read-only — it inspects and plans, doesn't implement unless you ask).
- **Not sure which tier** → let the kit decide: `/route "<describe the task>"`.

## Commands

| Command | What it does |
|---|---|
| `/route "<task>"` | Classifies the task, picks the cheapest sufficient tier, and dispatches to the right subagent — **without** changing your session model/effort. Use when unsure. |
| `/run-at <model> <effort> "<task>"` | You pick the exact tier; it dispatches a one-off subagent there — **without** changing your session model/effort. The manual counterpart to `/route`. Logs the choice to the routing ledger. |
| `/onboard` | Detects the repo's stack and writes a project-specific routing block + scope-guard pattern into its `CLAUDE.md`. Run once per project. |
| `/model sonnet` \| `/model opusplan` | Set the session/driver tier. `opusplan` = Opus plans, Sonnet executes. |
| `/effort low` | On expensive tiers, skip always-on thinking for routine work (no-op on Haiku). The real cost lever. |
| `/usage` | Tokens/cost this session, attributed to subagents/skills/plugins. The manual "cost" half of metrics. |

## `/run-at` shorthand

Two leading tokens, positional: **model** then **effort**. One-letter, full word, or joined
(`oh`, `sm`) all work. `h` = haiku in the model slot, high in the effort slot.

| Model (1st) | Effort (2nd) |
|---|---|
| `o` opus · `s` sonnet · `h` haiku | `l` low · `m` medium · `h` high · `x` xhigh |

```
/run-at s h "refactor the cart reducer"     # sonnet / high
/run-at oh "build the particle dissolve"     # opus / high
/run-at h m "fix the empty-state copy"       # haiku / medium
```

Your session `/model` and `/effort` stay put — only that one task runs at the tier you named.

## Invoking an agent directly

You don't always need `/route` — you can name the agent: *"Use the complex-implementer to
build the particle dissolve in HeroField."* The scope-guard still applies (UI-only agents are
blocked from risky paths and told to escalate).

## Reviewing performance (metrics)

The scope-guard logs every edit to `.claude/routing-log.jsonl` in the onboarded project
(tier attribution + allow/deny). To audit a session: run `/usage`, then ask Claude to read
the routing log + the session diff and report whether each task hit its intended tier, plus
any false blocks. (Auto-review via `/route-review` is BACKLOG Ticket 4.)

## Troubleshooting: "enabled ≠ registered" (Agent type not found)

**Symptom.** The plugin shows as on (`model-routing-kit@model-routing-kit: true` in
`settings.json`), its agents worked earlier, but now an escalation dies with
`Agent type 'complex-implementer' not found` — and *none* of the kit's agents are available.

**Why it happens.** `CLAUDE_CONFIG_DIR` is **shared across projects**. When you use plugins in a
sibling repo, Claude Code rewrites the **shared** registry files, and that churn can **evict the
kit's local marketplace**. The `enabled` flag stays `true`, but the marketplace that resolves it
is gone, so the agents never register at startup. **`enabled` is not `registered`** — and
`settings.json` alone can't tell you which: the registry files can.

The kit now ships a **SessionStart self-check** (`hooks/session-regcheck.sh`) that reads
the registry at session start and warns LOUDLY (once per distinct problem) when the kit is
enabled-but-not-registered — instead of letting you discover it only when an escalation fails.

**Diagnose** (replace `$CLAUDE_CONFIG_DIR` with your actual config dir, e.g. `~/.claude`):

```bash
# 1. Is the kit's MARKETPLACE present?
jq 'has("model-routing-kit")' "$CLAUDE_CONFIG_DIR/plugins/known_marketplaces.json"

# 2. Is the PLUGIN registered for THIS project (or at user/global scope)?
jq '.plugins["model-routing-kit@model-routing-kit"]' "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"
```

If (1) is `false` or (2) is `null` / only lists *other* projects' paths, the kit isn't registered
here.

**Fix:**

```
/plugin marketplace add <path-to-model-routing-kit>
/plugin install model-routing-kit@model-routing-kit
```

Install at **user/global scope**, not project/local — that way a sibling repo's plugin churn
can't evict it again. (`/onboard` recommends this too.)

**Until it's fixed — don't downgrade.** If an escalation agent is missing, do the task inline
**only if your session is already at or above the required tier**. Otherwise **stop and raise
`/model`** (or reinstall) — never run opus-grade work on a Sonnet driver just because the agent
vanished. This matters most under the recommended cheap-Sonnet driver, where the downgrade is
silent.

## Don't

- Don't route trivial edits to Opus.
- Don't route hard rendering/logic to the Haiku copy tier.
- Don't leave the driver on Opus "to be safe" — that's the expensive habit this kit exists to break.
- Don't trust `enabled: true` as proof the agents are registered — see "enabled ≠ registered" above.
