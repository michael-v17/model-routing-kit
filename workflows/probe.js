export const meta = {
  name: 'probe',
  description: 'Routing self-test: dispatch the same trivial task five different ways and report what each stage actually inherited — tier, system prompt, tool whitelist.',
  whenToUse: 'Run once per repo after /onboard, and again whenever a routed workflow behaves oddly or costs more than expected. Answers "is this kit actually routing anything in this session?" — the question no amount of doc can answer for you.',
  phases: [
    { title: 'Probe', detail: 'five dispatch forms, one trivial task, structural self-report' },
  ],
}

// ---------------------------------------------------------------------------
// Why this exists.
//
// Every routing guarantee in this kit is prose in a .md file, the default runs
// AGAINST it (docs: "Every agent in a workflow uses your session's model unless
// the script routes a stage to a different one"), and the failure path produces
// perfectly valid output — a stage that silently ran at the driver's tier answers
// your question just fine, only expensively. Those three conditions together mean
// no amount of normal use will ever surface the failure. Usage IS the failure.
//
// So this workflow makes the invisible half observable. It does NOT trust
// self-reported model names (models misreport their own version). The primary
// signal is STRUCTURAL and falsifiable:
//
//   architecture-auditor declares `tools: Read, Grep, Glob, Bash` — no Edit.
//   If agentType carries the whitelist, that probe MUST come back without Edit.
//   text-and-copy-editor declares `tools: Read, Edit, Grep, Glob` — no Bash.
//   If it comes back with Bash, the whitelist did not travel.
//
// The self-reported model is collected too, as an explicitly weak secondary
// signal. To settle the tier for real, read the run transcript afterwards —
// the last line of the output tells you where.
// ---------------------------------------------------------------------------

const REPORT = {
  type: 'object',
  additionalProperties: false,
  required: ['tools', 'selfReportedModel', 'promptStartsWith', 'sawProjectClaudeMd'],
  properties: {
    tools: { type: 'array', items: { type: 'string' }, description: 'every tool name available to you, verbatim' },
    selfReportedModel: { type: 'string', description: 'your model, as best you can tell — this is known-unreliable and treated as weak evidence' },
    effortSeen: { type: 'string', description: 'the reasoning effort you were given, or "unknown"' },
    promptStartsWith: { type: 'string', description: 'the first ~120 characters of your system prompt, verbatim' },
    sawProjectClaudeMd: { type: 'boolean', description: "true if the project's CLAUDE.md content was in your context" },
  },
}

const TASK = `Do not perform any task. Report on yourself only, into the structured output:

1. tools — every tool name available to you, verbatim, complete list.
2. selfReportedModel — which model you are.
3. effortSeen — the reasoning-effort level you were given, or "unknown".
4. promptStartsWith — the first ~120 characters of your system prompt, verbatim.
5. sawProjectClaudeMd — whether this project's CLAUDE.md content is in your context.

Be literal. Do not guess to be helpful: an inaccurate self-report defeats the whole point of this probe.`

const AUDITOR = 'model-routing-kit:architecture-auditor'
const COPY = 'model-routing-kit:text-and-copy-editor'

const PROBES = [
  {
    k: 'A-unrouted',
    how: 'agent(prompt) — nothing declared',
    opts: {},
    expect: { model: "the SESSION's model (this is the default the kit exists to prevent)", tools: 'full palette', prompt: 'generic' },
    check: r => ({
      hasEdit: r.tools.some(t => /^Edit$/i.test(t)),
      note: 'Whatever tier this one reports IS your unrouted default. Every stage of every dynamic workflow you have ever run without explicit routing ran here.',
    }),
  },
  {
    k: 'B-raw-haiku',
    how: "{ model: 'haiku' } — tier only, no role",
    opts: { model: 'haiku' },
    expect: { model: 'haiku', tools: 'full palette — NO scope guard', prompt: 'generic' },
    check: r => ({
      hasEdit: r.tools.some(t => /^Edit$/i.test(t)),
      note: 'Raw tier reproduces the cost brake and throws away the scope guard. If this probe has Edit and Bash, that is confirmed in your session.',
    }),
  },
  {
    k: 'C-agentType-auditor',
    how: `{ agentType: '${AUDITOR}' } — role only`,
    opts: { agentType: AUDITOR },
    expect: { model: 'opus (from the agent frontmatter), effort xhigh', tools: 'Read, Grep, Glob, Bash — NO Edit', prompt: "the kit's auditor prompt, verbatim" },
    check: r => ({
      pass: !r.tools.some(t => /^(Edit|Write)$/i.test(t)),
      why: 'architecture-auditor declares no Edit/Write. Edit present ⇒ the whitelist did NOT travel.',
    }),
  },
  {
    k: 'D-agentType+override',
    how: `{ agentType: '${AUDITOR}', model: 'sonnet', effort: 'low' } — role + your tier`,
    opts: { agentType: AUDITOR, model: 'sonnet', effort: 'low' },
    expect: { model: 'sonnet (your override beats the frontmatter opus)', tools: 'still Read, Grep, Glob, Bash — NO Edit', prompt: "still the kit's auditor prompt" },
    check: r => ({
      pass: !r.tools.some(t => /^(Edit|Write)$/i.test(t)),
      why: 'THIS is the form the kit workflows are built on: scope guard from the role, tier from you. If the whitelist survives here while the model changes, per-stage routing is fully working in this session.',
    }),
  },
  {
    k: 'E-agentType-copy',
    how: `{ agentType: '${COPY}' } — a different role, opposite whitelist`,
    opts: { agentType: COPY },
    expect: { model: 'haiku (frontmatter); effort is a no-op on haiku', tools: 'Read, Edit, Grep, Glob — NO Bash', prompt: "the kit's copy-editor prompt" },
    check: r => ({
      pass: r.tools.some(t => /^Edit$/i.test(t)) && !r.tools.some(t => /^Bash$/i.test(t)),
      why: 'Its own whitelist, not the auditor\'s. Edit present AND Bash absent ⇒ each role carries its own scope, not a shared default.',
    }),
  },
]

phase('Probe')
log('Dispatching 5 probes. Probe A is deliberately unrouted — it measures your default, so it runs at the session tier.')

// All five probes share one call site, so routing-lint sees a single spread and cannot
// tell them apart. Probe A's `opts` is deliberately `{}` — an unrouted control. That is
// the one stage in this whole plugin that is SUPPOSED to run at the driver's tier.
const out = await parallel(PROBES.map(p => () =>
  agent(TASK, { ...p.opts, label: `probe:${p.k}`, phase: 'Probe', schema: REPORT })
    .then(r => ({ ...p, r }))
    .catch(e => ({ ...p, r: null, error: String(e) }))
))

const rows = out.filter(Boolean)
const dead = PROBES.length - rows.filter(x => x.r).length

// A dead agentType probe is the single most important signal this file produces:
// `enabled ≠ registered`. The plugin can be on in settings and still have zero
// agents registered — and the docs do not say what an unresolved agentType does
// inside a workflow, so a null here is the only evidence you get.
const deadRoles = rows.filter(x => !x.r && x.opts.agentType).map(x => x.opts.agentType)
if (deadRoles.length) {
  log(`🔴 ${deadRoles.length} agentType probe(s) returned nothing: ${deadRoles.join(', ')}`)
  log('🔴 Most likely: the kit is enabled but its agents are NOT registered in this session (enabled ≠ registered), or CLAUDE_CONFIG_DIR points somewhere the plugin is not installed. Every routed workflow in this session is running unguarded. Fix before trusting any run.')
}

const models = rows.filter(x => x.r).map(x => x.r.selfReportedModel)
const allSame = models.length > 1 && new Set(models.map(m => (m || '').toLowerCase().replace(/[^a-z0-9]/g, ''))).size === 1
if (allSame) {
  log(`🔴 All ${models.length} probes self-report the SAME model ("${models[0]}") despite asking for three different tiers.`)
  log('🔴 Prime suspect: CLAUDE_CODE_SUBAGENT_MODEL is set. Per the docs it overrides the per-invocation `model` parameter AND the subagent frontmatter — one env var makes this entire kit inert, with no error. Check it, and set it to `inherit` to restore normal resolution.')
}

const findings = rows.map(x => {
  if (!x.r) return { probe: x.k, dispatch: x.how, result: 'DIED — no report' }
  const c = x.check(x.r)
  return {
    probe: x.k,
    dispatch: x.how,
    expected: x.expect,
    got: {
      selfReportedModel: `${x.r.selfReportedModel}  (weak signal — confirm in the transcript)`,
      effortSeen: x.r.effortSeen || 'unknown',
      tools: x.r.tools,
      promptStartsWith: x.r.promptStartsWith,
      loadedProjectClaudeMd: x.r.sawProjectClaudeMd,
    },
    scopeGuard: c.pass === undefined ? 'n/a (no role declared)' : (c.pass ? 'HELD ✅' : 'DID NOT HOLD 🔴'),
    note: c.why || c.note,
  }
})

const guarded = findings.filter(f => f.scopeGuard === 'HELD ✅').length
const broken = findings.filter(f => f.scopeGuard === 'DID NOT HOLD 🔴').length
log(`scope guard: ${guarded} held · ${broken} broke · ${dead} probes died`)

// One more silent-cost signal worth surfacing: an unrouted stage also loads the
// project CLAUDE.md that routed stages skip, so it is expensive on two axes.
const ctx = findings.filter(f => f.got && f.got.loadedProjectClaudeMd).map(f => f.probe)
if (ctx.length) log(`context note: ${ctx.join(', ')} loaded the project CLAUDE.md — routed stages usually do not, so an unrouted fan-out costs more prompt as well as more model.`)

return {
  summary: {
    probesDied: dead,
    scopeGuardHeld: guarded,
    scopeGuardBroken: broken,
    allProbesSameModel: allSame,
    unresolvedAgentTypes: deadRoles,
  },
  findings,
  howToSettleTheModelQuestion: [
    'Self-reported model names are unreliable. To settle the tier, read this run\'s transcript:',
    '  ~/.claude/projects/<session>/subagents/workflows/<runId>/   (or under $CLAUDE_CONFIG_DIR if you set it)',
    '  agent-<id>.meta.json  = what the stage ASKED for',
    '  agent-<id>.jsonl      → first .message.model  = what actually ANSWERED',
    'Anything that disagrees between those two files is a real routing failure, not a self-report artifact.',
  ],
}
