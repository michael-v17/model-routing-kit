export const meta = {
  name: 'audit',
  description: 'Repo audit with the ladder enforced: cheap parallel finders, diverse-cheap adversarial verify, one deciding synthesis. Every stage declares its tier.',
  whenToUse: 'Sweep N files/dimensions for a class of problem when coverage beats depth and findings must be judged by agents that did not produce them. Not for a single-surface change.',
  phases: [
    { title: 'Find', detail: 'one finder per target — kit role for the scope guard, cheap tier for the cost' },
    { title: 'Verify', detail: 'K skeptics per finding, different lenses, 2-of-K to survive' },
    { title: 'Decide', detail: 'one synthesis slot at the profile top tier' },
  ],
}

// ---------------------------------------------------------------------------
// PROFILES — the whole point of this file.
//
// Docs, verbatim: "Every agent in a workflow uses your session's model unless
// the script routes a stage to a different one or the CLAUDE_CODE_SUBAGENT_MODEL
// environment variable is set, which overrides both."
//
// So an unrouted fan-out costs N x the driver's tier. A saved workflow is how the
// routing stops being re-derived on every run. Each role below declares:
//   agentType -> system prompt + `tools` whitelist  (ALWAYS carried; the scope guard)
//   model/effort -> the tier, overriding whatever the agent's frontmatter says
// Measured 2026-08-05 (experiments/workflow-routing, round 2): passing both keeps
// the agent's prompt and whitelist while your tier wins. That is what lets a
// read-only auditor role run at sonnet instead of its native opus/xhigh.
//
// effort levels: low|medium|high|xhigh|max on Fable 5 / Opus 5 / Sonnet 5.
// Haiku does not support effort — the field vanishes from the transcript, no error.
// ---------------------------------------------------------------------------
const PROFILES = {
  // No opus anywhere. For routine repos and for burning less quota.
  frugal: {
    find:   { agentType: 'model-routing-kit:architecture-auditor', model: 'sonnet', effort: 'low' },
    verify: { model: 'sonnet', effort: 'medium' },
    decide: { model: 'sonnet', effort: 'xhigh' },
    lenses: 2,
  },
  // Default. Cheap fan-out, cheap-but-diverse verification, one expensive verdict.
  balanced: {
    find:   { agentType: 'model-routing-kit:architecture-auditor', model: 'sonnet', effort: 'medium' },
    verify: { model: 'sonnet', effort: 'high' },
    decide: { model: 'opus', effort: 'xhigh' },
    lenses: 3,
  },
  // High-stakes. Still never a frontier fan-out — fable only in the decide slot.
  frontier: {
    find:   { agentType: 'model-routing-kit:architecture-auditor', model: 'sonnet', effort: 'high' },
    verify: { model: 'opus', effort: 'high' },
    decide: { model: 'fable', effort: 'xhigh', fallback: { model: 'opus', effort: 'xhigh' } },
    lenses: 3,
  },
}

const LENSES = [
  { k: 'correctness', p: 'Does the described failure actually occur? Walk the code path. Refute if you cannot reach the bad state.' },
  { k: 'reachability', p: 'Is this code reachable in production, with real inputs? Refute dead code, test-only paths, and defended-upstream cases.' },
  { k: 'novelty', p: 'Is this already handled elsewhere — a guard, a validation layer, a type? Refute if the codebase already covers it.' },
]

// ---------------------------------------------------------------------------
// args arrives as STRUCTURED data, not a string. Docs, verbatim: "Claude passes
// the list as structured data, so the script can call array and object methods
// on args directly without parsing it first. If args is omitted, the global is
// undefined inside the script." So normalise every shape a human might mean.
//   /model-routing-kit:audit on src/api and src/db
//   /model-routing-kit:audit src/**, profile frugal, width 4
//   { targets: [...], question: '...', profile: 'frontier', width: 6, lenses: 2 }
// ---------------------------------------------------------------------------
function cfg(a) {
  const o = Array.isArray(a) ? { targets: a } : (typeof a === 'string' ? { targets: [a] } : (a || {}))
  const profileName = PROFILES[o.profile] ? o.profile : 'balanced'
  const width = Math.max(1, Math.min(Number(o.width) || 8, 12))   // hard cap: keeps the run under the kit's <=20 planning default
  const P = PROFILES[profileName]
  return {
    targets: (o.targets || o.paths || []).filter(Boolean).slice(0, width),
    question: o.question || o.q || 'correctness bugs, silent failure paths, and unhandled error cases',
    profileName,
    P,
    lenses: Math.max(1, Math.min(Number(o.lenses) || P.lenses, LENSES.length)),
    width,
  }
}

const C = cfg(args)

if (!C.targets.length) {
  log('No targets given. Invoke like: /model-routing-kit:audit on src/api, src/db — profile frugal, width 4')
  return { error: 'no targets', profiles: Object.keys(PROFILES) }
}

// The routing manifest. Returned at the end so the run's tiers are auditable from
// the result alone, without reading the transcript. This is the enforcement half
// that BACKLOG Ticket 10 point 3 asked for.
const manifest = {
  profile: C.profileName,
  width: C.width,
  targets: C.targets.length,
  lensesPerFinding: C.lenses,
  stages: {
    find: C.P.find,
    verify: { ...C.P.verify, lenses: LENSES.slice(0, C.lenses).map(l => l.k) },
    decide: C.P.decide,
  },
  projectedAgents: C.targets.length + '× find, then lenses × findings, then 1 decide',
}

log(`profile=${C.profileName} · targets=${C.targets.length} · lenses=${C.lenses}`)
log(`find=${C.P.find.model}/${C.P.find.effort} (${C.P.find.agentType}) · verify=${C.P.verify.model}/${C.P.verify.effort} · decide=${C.P.decide.model}/${C.P.decide.effort}`)
if (C.P.decide.fallback) log(`decide slot is fable — if it does not resolve this session it falls back to ${C.P.decide.fallback.model}/${C.P.decide.fallback.effort} (declared, not silent)`)

const FINDINGS = {
  type: 'object',
  additionalProperties: false,
  required: ['target', 'findings'],
  properties: {
    target: { type: 'string' },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['title', 'file', 'line', 'why'],
        properties: {
          title: { type: 'string' },
          file: { type: 'string' },
          line: { type: 'number' },
          why: { type: 'string', description: 'concrete failure scenario: inputs/state -> wrong output' },
          severity: { type: 'string', enum: ['high', 'medium', 'low'] },
        },
      },
    },
  },
}

const VERDICT = {
  type: 'object',
  additionalProperties: false,
  required: ['refuted', 'reason'],
  properties: { refuted: { type: 'boolean' }, reason: { type: 'string' } },
}

phase('Find')

// pipeline, not a barrier: each target's findings go to verification the moment
// THAT target's finder returns, instead of waiting for the slowest one.
// Measured 2026-08-05: barrier 48 s vs pipeline 29 s on the same work, -40%.
const perTarget = await pipeline(
  C.targets,

  t => agent(
    `Audit ${t} for: ${C.question}.

Report only findings you can point at with file and line, each with a concrete failure scenario (inputs or state -> wrong output). No style opinions, no speculative refactors. If the target is clean, return an empty findings array — that is a valid and useful answer.`,
    { ...C.P.find, label: `find:${t}`, phase: 'Find', schema: FINDINGS }
  ),

  (found, t) => {
    if (!found) return { target: t, dead: true, verified: [] }
    if (!found.findings.length) return { target: t, verified: [] }

    // Diverse-cheap verification: K lenses at the profile's verify tier beats one
    // expensive generalist. The skeptics never saw the finder's reasoning.
    return parallel(found.findings.map(f => () =>
      parallel(LENSES.slice(0, C.lenses).map(l => () => agent(
        `${l.p}

CLAIM UNDER TEST
  title: ${f.title}
  file:  ${f.file}:${f.line}
  why:   ${f.why}

Read the actual code before deciding. When uncertain, refute — a false finding costs more than a missed one here.`,
        { ...C.P.verify, label: `verify:${l.k}`, phase: 'Verify', schema: VERDICT }
      ))).then(votes => {
        const live = votes.filter(Boolean)
        const refuting = live.filter(v => v.refuted).length
        return {
          ...f,
          survives: live.length > 0 && refuting < Math.ceil(live.length / 2),
          votes: live.length,
          refuting,
          deadVotes: votes.length - live.length,
        }
      })
    )).then(vs => ({ target: t, verified: vs.filter(Boolean) }))
  }
)

// null != stop. A dead agent() resolves to null and the idiomatic .filter(Boolean)
// swallows it, leaving a result that looks complete and silently covered less.
// Count before filtering. An unresolved agentType is the most likely cause here —
// its failure mode is undocumented, so treat any dead find stage as suspect.
const live = perTarget.filter(Boolean)
const deadTargets = perTarget.length - live.length + live.filter(r => r.dead).length
if (deadTargets) {
  log(`⚠️  ${deadTargets}/${C.targets.length} find stages died — coverage is INCOMPLETE.`)
  log(`⚠️  If all of them died, suspect the agentType: "${C.P.find.agentType}" may not be registered in this session (enabled ≠ registered). Do not read the result as a clean audit.`)
}

const all = live.flatMap(r => r.verified)
const deadVotes = all.reduce((n, f) => n + (f.deadVotes || 0), 0)
if (deadVotes) log(`⚠️  ${deadVotes} verification votes died — some findings were judged by fewer skeptics than the profile asks for.`)

const survivors = all.filter(f => f.survives)
const killed = all.filter(f => !f.survives)
log(`${all.length} findings · ${survivors.length} survived · ${killed.length} refuted`)

phase('Decide')

let verdict = null
let decideRan = C.P.decide
if (survivors.length) {
  const prompt = `You are the deciding stage of a repo audit. ${survivors.length} findings survived adversarial verification (${killed.length} were refuted and are already discarded).

SURVIVORS
${JSON.stringify(survivors.map(f => ({ title: f.title, file: f.file, line: f.line, why: f.why, severity: f.severity, votes: `${f.votes - f.refuting}/${f.votes} upheld` })), null, 1)}

Produce, in markdown:
1. The ranked list, most severe first, each as one line: file:line — claim — why it matters.
2. Any pattern across findings that no single finding shows (that is the thing a fan-out can see and one agent cannot).
3. What this audit did NOT cover, given it looked at ${C.targets.length} target(s) for "${C.question}".
Be concrete. Do not pad.`

  const { fallback, ...decideTier } = C.P.decide
  verdict = await agent(prompt, { ...decideTier, label: 'decide', phase: 'Decide' })

  // Declared fallback, executed — never a silent drop.
  if (!verdict && fallback) {
    log(`⚠️  decide slot (${decideTier.model}/${decideTier.effort}) returned null — running the DECLARED fallback ${fallback.model}/${fallback.effort}`)
    verdict = await agent(prompt, { ...fallback, label: 'decide:fallback', phase: 'Decide' })
    decideRan = fallback
  }
  if (!verdict) log('⚠️  decide stage produced nothing — the survivor list below is raw, unsynthesised.')
}

return {
  routing: { ...manifest, decideActuallyRan: decideRan },
  coverage: { targets: C.targets, deadFindStages: deadTargets, deadVerificationVotes: deadVotes },
  counts: { found: all.length, survived: survivors.length, refuted: killed.length },
  survivors,
  refuted: killed.map(f => ({ title: f.title, file: f.file, line: f.line, refuting: `${f.refuting}/${f.votes}` })),
  verdict,
}
