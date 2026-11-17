# When to reach for a Workflow — the orchestration rubric

The ladder (CLAUDE.template.md) answers **who** runs a task: which model, at which effort.
This rubric answers the orthogonal question: **how many agents, under what control flow**.
Don't conflate them — a Workflow is not "more power", it's *more agents with deterministic
plumbing*; each stage inside it still routes by the ladder.

## The three orchestration rungs (climb one at a time, like the ladder)

| Rung | What it is | Reach for it when |
|---|---|---|
| **Inline** | The main session does it | One surface, one clear path, the conversation itself matters |
| **One subagent** | Agent tool / a named tier / `/run-at` | The task is self-contained and you want isolation (context cleanliness) or a different tier — but there is ONE of it |
| **Workflow** | Script-orchestrated multi-agent run | You need MANY agents with control flow you can trust (see rubric) |

## The rubric — go Workflow when ≥ 2 of these hold

- **Fan-out**: the work decomposes into ≥ 3 independent pieces (files, dimensions,
  lenses, sources) that don't share state while running.
- **Coverage beats depth-per-item**: audits, migrations, sweeps — missing an item is
  worse than treating each one a bit shallowly.
- **Independent verification**: findings must be judged by agents that did NOT produce
  them (the generator never grades its own work — adversarial verify, judge panels).
- **Won't fit one context**: reading/holding everything in a single window would blow it
  (or force lossy compaction mid-task).
- **Deterministic control flow**: loop-until-dry, count targets, dedup barriers,
  pipelines — logic you want in *code*, not in model judgment.

## Stay OFF Workflow when

- **One authorial voice matters** (a design doc, a spec, a README): one agent + one
  fresh-context review pass beats a committee every time.
- **The human is in the loop each step** (spec sessions, taste gates): that's a
  conversation, not an orchestration.
- **Single-file / single-surface change with a clear path**: the orchestration overhead
  IS the cost — a workflow here is a crane moving a box.
- **You can't name the work-list yet**: scout inline first (list the files, scope the
  diff), THEN pipeline over the discovered list. Hybrid is the normal shape, not a
  compromise.

## Archetype → rung (quick table)

| Task smell | Rung |
|---|---|
| "change this label / typo" | text-and-copy-editor (haiku) |
| "where does X live?" | built-in Explore |
| Feature on one surface | inline, or implementer if it needs a quiet room |
| Hard animation / algorithm / perf | complex-implementer (one subagent) |
| "audit the repo / find all the X" | Workflow: parallel finders → adversarial verify |
| Migrate N call-sites / files | Workflow: discover inline → pipeline transform (worktree isolation if stages write) → verify |
| "write the spec / design doc" | inline + ONE review agent (single voice) |
| Deep multi-dimension review | Workflow: dimension finders → verify (or native `/code-review` at high effort) |
| Second consecutive failure at a tier | STOP → human decides (redesign, or one deliberate Fable retry — see Fable rung) |

## The kit ships three workflows — use them before writing a new one

Everything below this line is doctrine. `workflows/` is that doctrine **executable**, with the
routing frozen so it isn't re-derived on every run:

| | |
|---|---|
| `/model-routing-kit:probe` | **run this first, once per repo.** Five dispatch forms, one trivial task → proves whether routing and the scope guard are actually working *in this session* |
| `/model-routing-kit:audit` | fan-out finders → K adversarial skeptics per finding → one deciding synthesis |
| `/model-routing-kit:migrate` | read-only plan per file → implementer applies → a different agent verifies the diff |

`audit` and `migrate` take `profile` — `frugal` / `balanced` (default) / `frontier` — which swaps
every stage's tier at once, plus `width` to scale the fan-out. **`probe` takes neither**: it is a
fixed 5-probe self-test, not a scalable fan-out. Full table, args, and brakes:
`workflows/README.md` — the single source of truth for what each script actually reads.

**Status:** written 2026-08-07 against the docs + the measurements below; the routing *forms* are
measured, the three *compositions* are not yet exercised end-to-end. Run `probe`, then `audit` on
one directory, before a repo-wide sweep.

## Inside a workflow, the ladder still rules — but only if the script SAYS so

**The default is the session's model, for every stage.** Claude writes these scripts, so
"unrouted" is what happens when nobody decides. Every `agent()` stage **MUST** declare its
tier. Fan-out finders and mechanical stages run CHEAP (sonnet or haiku, effort low/medium);
spend the expensive tiers on the few verify/judge/synthesize calls.

**The three ways to declare it are NOT interchangeable** (measured 2026-08-05, see §Measured):

| Form | The stage inherits | Use for |
|---|---|---|
| `{ agentType: 'model-routing-kit:<agent>' }` | system prompt + `tools` whitelist **always**; model + effort **only if that agent's frontmatter declares them** | **Prefer this** for any role the kit defines — it is the only form that carries the scope guard |
| `{ model, effort }` raw | the tier only — generic prompt, **full tool palette, no scope guard** | Mechanical stages with no role (finders, summarizers) |
| both together | prompt + tools from the agent; your `model`/`effort` override its frontmatter | Running a kit role at a non-default tier, once |

⚠️ **Built-in agents (`Explore`, `Plan`, `general-purpose`) declare no `model:`.** Inside a
workflow they run at the **driver's tier**, silently — so the read-only option the routing table
calls cheap is the most expensive one here. If a stage uses a built-in, pass `model` explicitly.

- **Default to `pipeline()`, not a barrier.** Measured: same 3 items, same 2 stages, durations
  crossed (20/8/2 s then 2/8/20 s) → **`parallel` barrier 48 s vs `pipeline` 29 s, −40%**. Both
  formulas held to the second: a barrier costs the *sum of per-stage maxima*; a pipeline costs the
  *slowest single-item chain*. Reach for a barrier only when stage N genuinely needs ALL of stage
  N-1 (dedup across the full set, early-exit on zero findings, "compare against the others").
  Caveat: subagent startup is ~3–5 s and hits both shapes equally, so with short stages the
  advantage dissolves into overhead.
- Diverse-cheap verification beats expensive-single: 3 sonnet skeptics with different
  lenses catch more than 1 opus generalist.
- Brakes are part of the design, not an afterthought: token/count budgets, post-pipeline
  null inspection, never-downgrade on unresolved agentType, log every silent cap.
- **`effort` is a silent no-op on Haiku.** A haiku stage asking `effort: 'low'` produced a
  transcript with no `effort` field at all, and no error. Don't count it as a brake there.

## Measured, not asserted

Everything marked "measured 2026-08-05" comes from
`the workflow-routing experiment notes (see this repo's evidence layer)` — 22 agents across
three runs, verified against each run's transcript (`agent-<id>.meta.json` = requested,
`.message.model` = resolved), **not** against self-reported model names and **not** via the kit's
telemetry hook, which had never fired (Ticket 13). To re-measure any claim here, run
`read-run.sh <run-dir>` on your own workflow.

One cost note that cuts the other way: **siblings in a fan-out share the prompt cache** — 9 of 12
agents in one run read the cached prompt instead of writing it. A fan-out's raw token total
overstates its real cost, so justify the ≤20 cap below on latency, coordination and quality
rather than on tokens alone.

## Cost + opt-in

A workflow multiplies agents — it spends usage quota by design. In interactive use it is
**opt-in**: the user asks for it in their own words (or the standing "ultracode" mode is
on). Don't infer it from "this task would benefit"; a task that would merely benefit gets
a single subagent or a proposal, not a fleet. A repo may upgrade this to a **standing
authorization** in its routing block (the frontier-driver preset: complex work — phase plans,
repo-wide sweeps, multi-perspective reviews — is pre-authorized as workflows; trivial and
single-file work stays inline).

## Fleet shape (harvested from the frontier-driver edition, 2026-07-16)

- **≤ 20 agent() calls per run** as the planning default — a design constraint, not a
  quota to fill: a 6-agent workflow that covers the work beats a padded 20. Honest
  decomposition needs more? Split into sequential workflows and read results between
  them — that checkpoint is a feature (course-correction), not overhead.
- **Pick the fleet workhorse deliberately.** Substantive stages (audit, complex
  implementation, adversarial verify) run one chosen tier; mechanical stages keep their
  cheap tiers per the routing table — never flatten the ladder to all-workhorse.
  (A money platform picked opus as workhorse; a marketing site usually needs only sonnet.)
- **The orchestrator adjudicates personally.** The fleet exists for context economy —
  reading/implementing/verifying happen OUTSIDE the driver's window — but every fleet
  result is adjudicated by the orchestrator, and critical decisions are never delegated
  to a fleet agent's final word.

## Fable × Workflow

- **Availability measured 2026-08-05, mechanics only:** `{model:'fable'}` on a workflow stage
  resolves to `claude-fable-5` for real — not a silent fallback — and `effort: 'xhigh'` is honored.
  The `agentType` + `model:'fable'` combination also works, keeping the agent's prompt and tool
  whitelist. What is **not** settled is whether it's worth 2× Opus 5 on real work; the rung stays
  provisional on cost/benefit, not on whether it runs.
- **Fable is the orchestrator's model, not a fleet model.** Its two legitimate places:
  the **driver session** itself (see presets below), and **at most 2–3 slots per run**
  for the genuinely critical stages — the deciding adversarial verdict on a finding the
  phase hinges on, the low-confidence re-audit of a critical invariant, the cross-cutting
  synthesis the orchestrator acts on directly. Pass explicitly:
  `{ model: 'fable', effort: 'xhigh' }`.
- **Declare the fallback in the plan**: fable unavailable on the account (check /model) →
  those slots run `opus/xhigh` — never silently dropped, never below that. (A missing
  named AGENT is a different case and stays a hard STOP — never downgrade.)
- **Never Fable fan-outs**: N × fable finders is the crane moving N boxes. If the fan-out
  needs to be smarter, fix the prompts or the decomposition, not the model tier.

## Driver presets (a creator/per-repo policy — pin one in the repo's routing block)

- **Quota-efficient (kit default):** driver = sonnet at effort high; opus is per-task
  escalation; fable only via the slots above. Right for routine-heavy repos.
- **Frontier-driver preset (2026-07-16):** driver = the best model the account
  has — fable where available, otherwise sonnet/high — for high-stakes orchestration.
  The principle that keeps it honest: *delegation moves work off the driver's context,
  never off its judgment.*
