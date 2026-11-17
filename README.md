<div align="center">

# model-routing-kit

**Evidence-first model routing for Claude Code — roles, a ledger, and measured decision layers.**

[![Claude Code](https://img.shields.io/badge/for-Claude%20Code-7c3aed?style=flat-square&logo=anthropic&logoColor=white)](https://claude.com/claude-code)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue?style=flat-square)](LICENSE)
[![Status](https://img.shields.io/badge/status-evidence%20complete%2C%20harness%20extracting-orange?style=flat-square)](docs/ROADMAP.md)

</div>

---

Subagent model routing in Claude Code is usually done by vibes: pick a tier per agent, hope it holds, never measure. This kit takes the opposite bet — **every routing claim ships with its measurement**.

Three pieces:

1. **Role→tier rules in code.** A small ladder of agents (haiku for mechanical text, sonnet for scoped implementation, opus for architecture and audits) with the routing decided per role, in frontmatter — judgeable, greppable, no runtime magic.
2. **A dispatch ledger.** Every routed dispatch logs requested model, resolved model, tokens, duration. The ledger is what makes the rest falsifiable: corpus, drift, and cost all come from it.
3. **Decision layers evaluated, not assumed.** Before wiring any automatic decider, we replay real and benchmark dispatches through it against a baseline.

## The headline evaluation: can a $0.042/MTok typed-decision model pick the tier?

We asked [Jev](https://typesafe.ai) (TypeSafe's typed-decision model) three calibrated yes/no questions per task brief — *could haiku / sonnet / opus complete this without escalating?* — one API call, three numbers — and the same three questions to a Haiku 5.5 loop. Criteria pre-registered before any run. Full harness in [`evidence/`](evidence/).

**Verdict: safe, not (yet) saving. No hook wired.**

| Criterion (pre-registered) | Jev | Haiku 5.5 loop |
|---|---|---|
| 0 under-routing on 43 real top-tier dispatches | **pass @ thr 0.7** (0/43) | only @ thr 0.9 |
| decision cost < $0.001 · p95 < 1 s | **$0.00003–5 · 0.22 s** | $~0.0001 · 1.44 s (fails) |
| ≥85% agreement, stratified SWE-bench (72) | 48–52% — **fail** | 38–43% — fail |
| beat `always-sonnet` on cost-quality | no (86% @ $12.7 vs 83% @ $10) | no |

Three findings worth stealing even if you never use this kit:

- **Calibration is structural.** Jev's per-tier probabilities came back monotone (opus ≥ sonnet ≥ haiku) on essentially every case; the generative baseline produced impossible orderings (opus < sonnet) on ~9/15 adversarial cases. A generative model can *pick* a tier; only typed probabilities can *drive a threshold policy*.
- **Benchmark difficulty labels are the wrong ground truth for routing.** SWE-bench per-instance outcomes say a haiku-class model solves ~67% of Verified — through agent loops of 15–32 calls. Both deciders read those same briefs as sonnet/opus work. "Can a cheap model in a loop eventually get there" ≠ "can this tier complete this brief in one dispatch." Routing evals need dispatch-shaped ground truth.
- **The under-routing failure mode is real but threshold-fixable** (0.7 cleared all 43 canaries), and over-routing is simply the price of safety. Pick which one you can afford.

Also measured, smaller: a four-arm router smoke (Haiku loop · GPT-6 Luna loop · OpenAI Decisions · Jev) on a 4-item instrument check — Jev fastest (p50 0.15 s) and cheapest ($0.000025/call), all arms 4/4.

## Positioning

- [`subagent-model-routing`](https://github.com/Buckeyes22/subagent-model-routing) — cross-CLI shims so each host can delegate to other vendors' CLIs. Complementary: this kit routes *within* one host, by role, with measurements.
- [Rayline](https://news.ycombinator.com/item?id=48448372) — a trained ML router for Claude Code subagents. Different bet: they trust the router; we wire a decider only after a replay says it's safe, and keep rules that fail loudly.
- GitHub's native `gh-aw` model-routing — engine-level routing with cost goals. This kit works at the subagent-role level inside Claude Code and adds the ledger.

## Status & roadmap

The evidence layer is complete and reproducible (below). The harness pieces (agent ladder, ledger hook, audit/migrate workflows) are being extracted from a production setup — see [docs/ROADMAP.md](docs/ROADMAP.md). Contributions welcome once the extraction lands.

## Reproduce the evaluation

```bash
cd evidence
./run.sh cases-adversarial.jsonl   # needs Keychain secrets (see run.sh) — or bring your own keys
python3 score.py
```

`score.py` prints the threshold sweep, the cost-quality frontier against `always-haiku/sonnet/opus` baselines, and the canary under-routing check. Cases: 72 stratified SWE-bench Verified briefs (public), 15 adversarial probes (hand-written, in-repo), and 43 real dispatch canaries (probabilities only — the briefs come from private repositories and are withheld).

## License

[MIT](LICENSE) © 2026 michael-v17
