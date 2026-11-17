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
sonnet/low → sonnet/med → sonnet/high → sonnet/xhigh → opus/med → opus/high → opus/xhigh
```

(Sonnet 5, 2026-06-30: effort is load-bearing on sonnet — sonnet/xhigh approaches Opus 4.8
for most audit work, so it's a real rung, not a gap. ⚠️ That rung was calibrated against
**Opus 4.8**; since 2026-07-24 `opus` resolves to **Opus 5**, so the gap it closes is wider
than measured — re-check before leaning on it for audit work.) Two rungs are named agents —
`implementer` (sonnet/high) and `complex-implementer` (opus/high).
The in-between combos (sonnet/med, sonnet/xhigh, opus/med, opus/low) aren't; hit them with
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

## Workflows — la escalera, ejecutable

Tres workflows shippeados congelan el ruteo por etapa para que no se re-derive (y se salte) en
cada corrida. Sin uno, una etapa `agent()` sin tier declarado hereda el tier del *driver* —
medido en 64% de los tokens de una corrida real de 26 agentes, sólo por etapas que no declararon
tier.

| Invocar | Qué hace |
|---|---|
| `/model-routing-kit:probe` | auto-test de ruteo — correr primero, una vez por repo: cinco formas de despacho, una tarea trivial, self-report estructural (tools + prompt, no el nombre de modelo auto-reportado) |
| `/model-routing-kit:audit` | fan-out de finders → K escépticos adversariales por hallazgo → una síntesis decisoria |
| `/model-routing-kit:migrate` | plan read-only por archivo → implementer aplica → un agente distinto verifica el diff |

Cada uno toma un `profile` (`frugal` / `balanced` / `frontier`) que fija el tier de todas las
etapas a la vez. `args` es estructurado, no posicional — lenguaje natural funciona:

```
/model-routing-kit:audit on src/api and src/db, profile frugal, width 4
```

**Todavía no corrido end-to-end** (shippeado 2026-08-07, v0.5.0) — correr `probe` primero, después
`audit` en un solo directorio antes de un barrido de todo el repo. Detalle de perfiles, args y
frenos: `workflows/README.md`.

## `/run-at` shorthand

Two leading tokens, positional: **model** then **effort**. One-letter, full word, or joined
(`oh`, `sm`) all work. `h` = haiku in the model slot, high in the effort slot.

| Model (1st) | Effort (2nd) |
|---|---|
| `o` opus · `s` sonnet · `h` haiku · `f` fable | `l` low · `m` medium · `h` high · `x` xhigh |

```
/run-at s h "refactor the cart reducer"     # sonnet / high
/run-at oh "build the particle dissolve"     # opus / high
/run-at h m "fix the empty-state copy"       # haiku / medium
/run-at f x "the fully bespoke gesture-driven modal"   # fable / xhigh
```

Your session `/model` and `/effort` stay put — only that one task runs at the tier you named.

**Fable is a deliberate top-of-ladder call** (CLAUDE.template.md already said `/run-at fable
high "<task>"` was the way to reach it — this table just catches the implementation up to that
promise). Reserve it for genuinely hard AND fully bespoke work — no existing pattern to extend,
the kind of thing that stresses even Opus. Access follows plan tier (included up to 50% of
weekly usage on Max plans/Premium seats, pay-as-you-go via usage credits on Pro/Standard
seats/API) — if `fable` doesn't resolve this session (allowance spent, no credits, or the seat
never included it), `/run-at` **falls back to opus at the same effort automatically** — a
*declared* substitution, not a silent one. It always states which model actually ran. Never
falls back below opus for a task you explicitly routed to fable.

## Invoking an agent directly

You don't always need `/route` — you can name the agent: *"Use the complex-implementer to
build the particle dissolve in HeroField."* The scope-guard still applies (UI-only agents are
blocked from risky paths and told to escalate).

## Reviewing performance (metrics)

Two writers feed `.claude/routing-log.jsonl` in an onboarded project:

- **`/run-at`** → `source:"manual"` (your explicit tier choices)
- **`agent-telemetry.sh`** → `source:"agent"` — one line per completed subagent with
  `total_tokens` + cache split, duration, tool count, and **`model_mismatch`** (the tier asked
  for vs the `resolvedModel` that actually ran). Ticket 4 part 1, shipped in 0.4.0.

To audit a session, read the log + the session diff and ask whether each task hit its intended
tier, plus any false blocks. (Auto-review via `/route-review` is Ticket 4 part 2 — worth writing
only once the log holds real sessions, not test runs.)

### Verifying the telemetry works (once, after installing ≥ 0.4.0)

**0. Install, then restart.** Hooks load at session start. `plugin install` on an already
installed plugin answers *"already installed"* and upgrades nothing — the command that upgrades
is **`update`**:

```bash
claude plugin marketplace update model-routing-kit
claude plugin update model-routing-kit@model-routing-kit     # NOT install
# then open a NEW session — the running one still has the old hooks
```

Each `CLAUDE_CONFIG_DIR` is a separate installation: repeat there. Prefer **`--scope user`** in
each — a `local`/`project` entry pinned to a sibling repo doesn't count for this project, and a
stale one can shadow the global install.

**1. Generate contrast across tiers** (one of each is enough):

```
/run-at h l "fix the typo in <some string>"           -> expect haiku
use visual-polish to adjust spacing on <some view>     -> expect sonnet
use architecture-auditor to review <something risky>   -> expect opus
```

**2. Read what landed:**

```bash
jq -c 'select(.source=="agent")
       | {agent, requested_model, resolved_model, model_mismatch, total_tokens}' \
   .claude/routing-log.jsonl
```

| Result | Means |
|---|---|
| **empty** after delegating | the hook never loaded — installation problem, see Troubleshooting below |
| `model_mismatch: false` | routing is being honored ✅ |
| any `model_mismatch: true` | something overrode the tier. First suspect: `CLAUDE_CODE_SUBAGENT_MODEL` — it beats both a call's `model` *and* an agent's frontmatter (`echo $CLAUDE_CODE_SUBAGENT_MODEL`; set and not `inherit` = culprit). Also possible: an org `availableModels` allowlist, or `--fallback-model` |

**3. The question that actually matters** — after a few sessions of *real work*, not test runs:

```bash
jq -s 'map(select(.source=="agent")) | group_by(.agent)
       | map({agent: .[0].agent, runs: length, tokens: (map(.total_tokens//0)|add)})' \
   .claude/routing-log.jsonl
```

The kit's dominant finding was that **~90% of the bill was the Opus driver session, not the
subagents**. If this shows subagent tokens are still a rounding error, that reconfirms the driver
model is the real lever — the evidence needed to re-decide the default-driver policy and the
Fable rung, both frozen as provisional since Opus 5.

**Steps 1–2 prove the instrument works; step 3 produces evidence to decide with. Don't confuse
them** — three test commands are not a dataset.

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

## Guardia: ¿la tabla de routing nombra agentes que resuelven?

`hooks/routing-table-check.sh` responde una pregunta distinta a la de `session-regcheck.sh`: no
"¿está registrado el plugin?" sino "cada agente NOMBRADO en la tabla de routing de *este proyecto*
(CLAUDE.local.md / CLAUDE.md), ¿resuelve de verdad desde acá?" Un proyecto puede vendorizar sus
propios agentes tuneados en `.claude/agents/` y vendorizar sólo *algunos* mientras la tabla sigue
ruteando a los cinco — el primer síntoma es una escalada muriendo a mitad de tarea con "Agent type
not found".

Corre de dos maneras:

- **como hook SessionStart** (cableado en `hooks.json`, encadenado después de
  `session-regcheck.sh`) — silencioso si está sano, avisa una vez por firma de problema si no.
- **como comando suelto**, en cualquier proyecto, bajo cualquier config dir, con o sin plugin:

```bash
bash hooks/routing-table-check.sh <proyecto> [--verbose]
```

Clasifica cada agente nombrado en uno de cuatro cubos — tuneado al proyecto (`.claude/agents/`),
vía plugin (genérico), built-in (`Explore`/`Plan`/`general-purpose`), o no resuelve — y nunca dice
que degrades en silencio: si falta un agente que nombra, hacé la tarea inline sólo si tu sesión ya
está al tier requerido o por encima; si no, parate y subí `/model`.

## Don't

- Don't route trivial edits to Opus.
- Don't route hard rendering/logic to the Haiku copy tier.
- Don't leave the driver on Opus "to be safe" — that's the expensive habit this kit exists to break.
- Don't trust `enabled: true` as proof the agents are registered — see "enabled ≠ registered" above.
