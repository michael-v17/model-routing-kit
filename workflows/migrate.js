export const meta = {
  name: 'migrate',
  description: 'Apply one mechanical change across N files with the ladder enforced: read-only plan, cheap implementer per file, independent verify of each diff.',
  whenToUse: 'A known change repeated across many call-sites (rename, API swap, import move, pattern replacement). Not for a change whose shape you still have to discover — scout inline first, then run this over the list.',
  phases: [
    { title: 'Plan', detail: 'read-only per file: what exactly changes here, and what could break' },
    { title: 'Apply', detail: 'implementer per file, tier from the profile' },
    { title: 'Verify', detail: 'a different agent reads the diff it did not write' },
  ],
}

// ---------------------------------------------------------------------------
// Same routing contract as audit.js. Duplicated on purpose: workflow scripts are
// self-contained (no imports available), so each file carries its own profiles.
// If you change a tier here, change it there too — or run /model-routing-kit:probe
// to see what actually resolved.
//
// The implementer tiers mirror the kit's own ladder (CLAUDE.template.md):
//   implementer          = sonnet/high  — moderately hard, multi-step, stateful
//   complex-implementer  = opus/high    — animation, algorithms, perf, concurrency
// A mechanical migration is neither: it is below `implementer`'s native tier, so
// frugal drops effort rather than reaching for a smaller model — the ladder's own
// rule is escalate (and de-escalate) EFFORT before MODEL.
// ---------------------------------------------------------------------------
const PROFILES = {
  frugal: {
    plan:   { agentType: 'model-routing-kit:architecture-auditor', model: 'sonnet', effort: 'low' },
    apply:  { agentType: 'model-routing-kit:implementer', model: 'sonnet', effort: 'low' },
    verify: { agentType: 'model-routing-kit:architecture-auditor', model: 'sonnet', effort: 'low' },
  },
  balanced: {
    plan:   { agentType: 'model-routing-kit:architecture-auditor', model: 'sonnet', effort: 'medium' },
    apply:  { agentType: 'model-routing-kit:implementer', model: 'sonnet', effort: 'high' },
    verify: { agentType: 'model-routing-kit:architecture-auditor', model: 'sonnet', effort: 'medium' },
  },
  // Risky migration (schemas, adapters, persistence). The plan and the verify climb;
  // the apply stays sonnet because writing the same edit N times is not the hard part.
  frontier: {
    plan:   { agentType: 'model-routing-kit:architecture-auditor', model: 'opus', effort: 'xhigh' },
    apply:  { agentType: 'model-routing-kit:complex-implementer', model: 'sonnet', effort: 'high' },
    verify: { agentType: 'model-routing-kit:architecture-auditor', model: 'opus', effort: 'high' },
  },
}

function cfg(a) {
  const o = Array.isArray(a) ? { targets: a } : (typeof a === 'string' ? { change: a } : (a || {}))
  const profileName = PROFILES[o.profile] ? o.profile : 'balanced'
  const width = Math.max(1, Math.min(Number(o.width) || 8, 12))
  return {
    targets: (o.targets || o.paths || o.files || []).filter(Boolean).slice(0, width),
    change: o.change || o.task || '',
    isolate: o.isolate === true,     // opt-in: see the note logged below
    profileName,
    P: PROFILES[profileName],
    width,
  }
}

const C = cfg(args)

if (!C.targets.length || !C.change) {
  log('Needs both a file list and a change. Example: /model-routing-kit:migrate — change "replace getUser() with fetchUser()" across src/a.ts, src/b.ts, profile balanced')
  return { error: 'missing targets or change', profiles: Object.keys(PROFILES) }
}

log(`profile=${C.profileName} · files=${C.targets.length} · isolate=${C.isolate}`)
log(`plan=${C.P.plan.model}/${C.P.plan.effort} · apply=${C.P.apply.model}/${C.P.apply.effort} (${C.P.apply.agentType}) · verify=${C.P.verify.model}/${C.P.verify.effort}`)
if (C.isolate) {
  log('isolate=true — each apply stage runs in its own git worktree. Agents cannot collide, but the edits land in SEPARATE worktrees you have to merge yourself. Use only when two stages would touch the same file.')
} else {
  log('isolate=false (default) — all stages edit the working tree directly. Fine when each target is a distinct file. Fleet agents always run in acceptEdits, so these edits are auto-approved: commit or stash first.')
}

const PLAN = {
  type: 'object',
  additionalProperties: false,
  required: ['file', 'applicable', 'edits', 'risks'],
  properties: {
    file: { type: 'string' },
    applicable: { type: 'boolean', description: 'false if this file does not actually need the change' },
    edits: { type: 'array', items: { type: 'string' }, description: 'each edit as: line ~N, old -> new' },
    risks: { type: 'array', items: { type: 'string' }, description: 'what could break — callers, types, tests, runtime behaviour' },
  },
}

const CHECK = {
  type: 'object',
  additionalProperties: false,
  required: ['ok', 'problems'],
  properties: {
    ok: { type: 'boolean' },
    problems: { type: 'array', items: { type: 'string' } },
    unplanned: { type: 'array', items: { type: 'string' }, description: 'changes present in the diff that the plan did NOT call for — scope creep' },
  },
}

phase('Plan')

const results = await pipeline(
  C.targets,

  // Read-only. architecture-auditor's `tools` whitelist has no Edit/Write, so this
  // stage structurally cannot start editing early — the scope guard travels with
  // agentType even though the tier here is the profile's, not the agent's.
  f => agent(
    `Plan this change for ONE file. Do not edit anything.

FILE:   ${f}
CHANGE: ${C.change}

Read the file. Say precisely which edits it needs (line, old, new), and what could break — callers, types, tests, runtime behaviour. If the file does not actually need this change, say so with applicable:false; a false positive that gets "migrated" anyway is the expensive outcome here.`,
    { ...C.P.plan, label: `plan:${f}`, phase: 'Plan', schema: PLAN }
  ),

  (plan, f) => {
    if (!plan) return { file: f, dead: 'plan' }
    if (!plan.applicable) return { file: f, skipped: 'not applicable', risks: plan.risks }

    // The routing stays spelled out at the call site on purpose: an options object
    // assembled somewhere else hides the tier from both the reader and routing-lint.
    return agent(
      `Apply exactly this plan to ${f}. Nothing else.

PLANNED EDITS
${plan.edits.map(e => `- ${e}`).join('\n')}

KNOWN RISKS
${plan.risks.map(r => `- ${r}`).join('\n')}

Rules: make only the edits listed. Do not refactor, rename anything extra, reformat, or "improve" surrounding code. If an edit no longer matches the file, stop and report which one — do not improvise a replacement. Report what you changed, line by line.`,
      {
        ...C.P.apply,
        ...(C.isolate ? { isolation: 'worktree' } : {}),
        label: `apply:${f}`,
        phase: 'Apply',
      }
    ).then(applied => ({ file: f, plan, applied }))
  },

  (r, f) => {
    if (!r || r.dead || r.skipped || !r.applied) return r || { file: f, dead: 'apply' }

    // The verifier never saw the implementer's reasoning — only the plan and the
    // diff. Same principle the kit applies everywhere: the writer does not grade
    // its own work.
    return agent(
      `Verify a migration diff you did not write.

FILE: ${r.file}
THE CHANGE THAT WAS ASKED FOR: ${C.change}

THE PLAN IT WAS SUPPOSED TO FOLLOW
${r.plan.edits.map(e => `- ${e}`).join('\n')}

Read the file's current state and \`git diff -- ${r.file}\`. Answer two questions:
1. Was the planned change applied correctly and completely?
2. Does the diff contain anything the plan did NOT call for? List every unplanned change — reformatting, renames, removed comments, "while I was here" edits. Scope creep across N files is how a mechanical migration turns into an unreviewable diff.`,
      { ...C.P.verify, label: `verify:${r.file}`, phase: 'Verify', schema: CHECK }
    ).then(check => ({ ...r, check }))
  }
)

// Count deaths before filtering: a stage that died leaves a file half-migrated or
// unverified, and .filter(Boolean) would make the run look complete.
const live = results.filter(Boolean)
const dead = results.length - live.length + live.filter(r => r.dead).length
const skipped = live.filter(r => r.skipped)
const done = live.filter(r => r.check)
const unverified = live.filter(r => r.applied && !r.check)
const failed = done.filter(r => !r.check.ok)
const creep = done.filter(r => (r.check.unplanned || []).length)

if (dead) log(`⚠️  ${dead} file(s) had a stage die — those files may be half-migrated. Check git status before doing anything else.`)
if (unverified.length) log(`⚠️  ${unverified.length} file(s) were EDITED but not verified — the verify stage died. Review these by hand: ${unverified.map(r => r.file).join(', ')}`)
if (failed.length) log(`⚠️  ${failed.length} file(s) failed verification`)
if (creep.length) log(`⚠️  ${creep.length} file(s) contain changes the plan did not call for`)
log(`${done.length} verified · ${skipped.length} skipped as not-applicable · ${failed.length} failing`)

return {
  routing: { profile: C.profileName, isolate: C.isolate, stages: C.P },
  coverage: { requested: C.targets.length, deadStages: dead, editedButUnverified: unverified.map(r => r.file) },
  ok: done.filter(r => r.check.ok && !(r.check.unplanned || []).length).map(r => r.file),
  skipped: skipped.map(r => ({ file: r.file, why: r.skipped, risks: r.risks })),
  failing: failed.map(r => ({ file: r.file, problems: r.check.problems })),
  scopeCreep: creep.map(r => ({ file: r.file, unplanned: r.check.unplanned })),
}
