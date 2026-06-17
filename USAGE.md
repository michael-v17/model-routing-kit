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
| **Genuinely hard, ONE task** — complex animation/canvas/WebGL/particles, tricky algorithm, perf rendering, intricate state | **complex-implementer** | **opus, effort high** |
| Risky / "is this change safe?" — data, schema, stores, routing, contracts, migrations | **architecture-auditor** (inspect & plan first) | opus, effort xhigh |
| Big multi-section sweep / whole feature | **opusplan** (`/model opusplan`) | opus plans → sonnet executes |

**Rule of thumb:** pick the *lowest* plausible tier; escalate only on a real risk signal
(touches persistence/auth/payments, spans >5 files, mixes UI with data, or a smaller model
already failed at it).

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

## Don't

- Don't route trivial edits to Opus.
- Don't route hard rendering/logic to the Haiku copy tier.
- Don't leave the driver on Opus "to be safe" — that's the expensive habit this kit exists to break.
