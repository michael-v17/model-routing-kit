# Shipped workflows — the routing, frozen

`WORKFLOW-RUBRIC.md` says what the routing should be. These files **are** it.

The gap they close is Ticket 10. The docs are explicit:

> "Every agent in a workflow uses your session's model unless the script routes a stage to a
> different one **or the `CLAUDE_CODE_SUBAGENT_MODEL` environment variable is set, which
> overrides both**."

and Claude writes dynamic workflow scripts, not you — so **unrouted is what happens when nobody
decides**. A driver on `opus / xhigh` with ultracode on produces a fan-out of N agents at
opus/xhigh. That is not a limitation of the Workflow tool; it is the default. Saving a workflow
is what freezes the routing so it stops being re-derived on every run.

Measured in one real run (26 agents, 2026-08-07): 18 stages declared `sonnet` and resolved to
`claude-sonnet-5`; the 8 that declared nothing resolved to `claude-opus-5`, the driver — **64% of
1.49M tokens moved off the driver tier by declaring it.** Per-stage routing works. Not declaring
it is the whole problem.

## The three

| Invoke | What it is |
|---|---|
| `/model-routing-kit:audit` | fan-out finders → K adversarial skeptics per finding → one deciding synthesis |
| `/model-routing-kit:migrate` | read-only plan per file → implementer applies → a different agent verifies the diff |
| `/model-routing-kit:probe` | routing self-test: five dispatch forms, one trivial task, structural self-report |

The slash name comes from `meta.name`, not the filename, and is namespaced by the plugin
("Plugin workflows are namespaced by the plugin name").

## Profiles — the knob

`audit` and `migrate` take `profile`, and each profile is a table of `{agentType, model, effort}`
per stage — change the profile, change every tier in the run at once. **`probe` takes no
arguments at all**: it is a fixed five-probe self-test, not a scalable fan-out. The argument
table below is the authority; if any other doc says otherwise, that doc is wrong.

| | `frugal` | `balanced` (default) | `frontier` |
|---|---|---|---|
| **audit** find / verify / decide | sonnet low / sonnet med / sonnet xhigh | sonnet med / sonnet high / **opus xhigh** | sonnet high / **opus high** / **fable xhigh** |
| **migrate** plan / apply / verify | sonnet low ×3 | sonnet med / sonnet high / sonnet med | **opus xhigh** / sonnet high / **opus high** |

Three rules are baked in and worth knowing before you edit them:

- **Never a frontier fan-out.** `fable` appears in exactly one slot, `audit`'s `decide`, and it
  declares its fallback (`opus/xhigh`) which the script actually *executes* if the slot returns
  null. N × fable finders is the crane moving N boxes.
- **Effort de-escalates before model does.** `frugal` drops `implementer` from sonnet/high to
  sonnet/low rather than to haiku — the ladder's own rule, run backwards.
- **The expensive tier goes on the verdict, not the search.** Finding is fan-out; deciding is one
  call. That is where an `opus`/`fable` slot pays for itself.

## The form that does the real work

```js
{ agentType: 'model-routing-kit:architecture-auditor', model: 'sonnet', effort: 'medium' }
```

Both at once. The three dispatch forms are **not** interchangeable:

| Form | Carries | Use for |
|---|---|---|
| `{ agentType }` | prompt + `tools` whitelist **always**; model/effort **only if the frontmatter declares them** | a kit role at its native tier |
| `{ model, effort }` | the tier only — generic prompt, full tool palette, **no scope guard** | mechanical stages with no role |
| **both** | prompt + whitelist from the role, **your tier wins** | ← what these workflows use |

That third row is the answer to "I want an opus driver but sonnet agents": the role gives you the
system prompt and the tool restriction (an `architecture-auditor` has no `Edit`, so it
structurally cannot start editing), and the explicit `model`/`effort` give you the cost brake —
without the role's native opus/xhigh riding along into a fan-out.

⚠️ Built-in agents (`Explore`, `Plan`, `general-purpose`) declare no `model:`. Inside a workflow
they run at the **driver's** tier. Always pass `model` with them.

## Arguments

`args` arrives as **structured data**, not a string — Claude builds it from what you type, so
plain language works and there is no positional parsing:

```
/model-routing-kit:audit on src/api and src/db, profile frugal, width 4
/model-routing-kit:migrate — replace getUser() with fetchUser() across src/a.ts and src/b.ts, profile frontier
```

| key | audit | migrate |
|---|---|---|
| `targets` / `paths` / `files` | ✓ | ✓ |
| `profile` | ✓ | ✓ |
| `width` | cap on targets (max 12) | idem |
| `question` | what to look for | — |
| `change` | — | the edit to apply (required) |
| `lenses` | skeptics per finding (max 3) | — |
| `isolate` | — | `true` → each apply runs in its own git worktree |

`width` is capped at 12 in code so a run stays inside the kit's ≤20 `agent()` planning default.
Raise the constant if you mean it; don't let a prompt raise it for you.

## Brakes these ship with

Written into the scripts because a guarantee in prose, with the default against it and a valid
output on the failure path, is a failure nobody will ever notice:

- **Dead stages are counted before `.filter(Boolean)`.** A dead `agent()` resolves to `null`; the
  idiomatic filter swallows it and the run looks complete while covering less. Every script logs
  the deaths and returns a `coverage` block.
- **A dead `agentType` is called out by name.** The docs do not say what an unresolved `agentType`
  does inside a workflow — so a null there is treated as the loudest signal in the run
  (`enabled ≠ registered`), not a hiccup.
- **`migrate` names files it edited but could not verify.** Half-migrated is worse than
  unmigrated, and it must never be silent.
- **The `fable` fallback runs.** It is not a comment saying what should happen.
- **Every run returns its `routing` manifest** — profile, per-stage tier, and which tier the
  decide slot *actually* ran. The routing becomes auditable from the result, without the transcript.

## Verify it actually routed

`/model-routing-kit:probe` first. If its `agentType` probes come back with `Edit`, the scope guard
is not travelling; if all five probes report the same model, suspect `CLAUDE_CODE_SUBAGENT_MODEL`
(it overrides the per-invocation `model` **and** the agent's frontmatter — one env var, whole kit
inert, no error).

Self-reported model names are unreliable. The transcript is not:

```
<config-dir>/projects/<session>/subagents/workflows/<runId>/
  agent-<id>.meta.json   # what the stage ASKED for
  agent-<id>.jsonl       # first .message.model = what ANSWERED
```

`<config-dir>` is `~/.claude` unless `CLAUDE_CONFIG_DIR` is set — and if it is set, the plugin has
to be installed *under that directory* or none of these workflows resolve at all.

## Caveats

- **Not exercised end-to-end yet.** Written 2026-08-07 against the docs plus the measured findings
  in `experiments/workflow-routing`. The routing forms are measured; these three compositions are
  not. Run `probe` first, then `audit` on one directory before a repo-wide sweep.
- **Scripts are self-contained** — no imports — so the profile tables are duplicated per file. If
  you change a tier, change it everywhere, or `probe` will tell you later.
- **Fleet agents always run in `acceptEdits`**, whatever your session's permission mode. `migrate`
  edits your working tree. Commit or stash first.
- **Resume is same-session only.** Exiting Claude Code mid-run starts fresh next time.
