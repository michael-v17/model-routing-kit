# Learnings — Jev as the tier decider (2026-11-17)

## What we learned

1. **Jev qualifies as a *safe* decision layer, not (yet) a *saving* one.** Pre-registered criteria: safety (0/43 under-routing on real opus-work canaries at thr ≥ 0.7) and decision economics ($0.00003–0.00005, p95 0.22 s) passed decisively; routing quality on SWE-bench Verified (72 stratified) did not — max 52% agreement, and the cost-quality frontier never beats `always-sonnet` (86% solved at cost index 12.7 vs 83% at 10.0; the index is list price per 1M output tokens, equal tokens per task assumed, see `score.py`). Per the pre-registered rule: **no hook gets wired**; the kit keeps its role rules, now with the evidence attached.
2. **Benchmark-derived "cheapest solving tier" labels conflate agent-loop persistence with single-dispatch capability.** SWE-bench per-instance outcomes say Claude-Haiku-class + mini-SWE-agent solves ~67% of Verified — via 15–32 api_calls per instance. Both deciders (Jev and Haiku) read the same briefs as sonnet/opus work. The label answers "can a cheap model in a loop eventually get there"; the router's question is "can this tier complete this brief in one dispatch". External difficulty labels for routing need dispatch-shaped ground truth, not agent-loop outcomes.
3. **Calibration is structural, not stylistic.** Jev's per-tier probabilities came back monotone (opus ≥ sonnet ≥ haiku) on effectively every case; Haiku 5.5's were incoherent on ~9/15 adversarial cases (opus < sonnet — impossible orderings) and it needs thr 0.9 to stop under-routing real opus work. A generative model can pick; only a typed-decision model's numbers can *drive a threshold policy*. This — not accuracy — is where the decision-layer category actually differs.

## What surprised us

- The real dispatch corpus was **one-sided**: 597 subagent runs on this machine, 43 unique kit cases, **all opus-tier**. Cheap-tier work happens in the main session; subagents are dispatched only for top-tier review. The kit's own thesis (oversized dispatches) had no local evidence to replay — the eval only became possible with external data.
- The workflow-harness brief wrapper is byte-identical for the first 200+ chars of every workflow dispatch — dedup on brief-prefix silently collapsed 389 runs into 2 cases.

## Links

- Feeds the kit decision-layer question (answered NO-for-now, with the safety qualification).
- Refines the Jev prior-art notes: the under-routing failure mode is real and threshold-fixable (0.7); over-routing is the price of safety.
- Method note for any future routing eval: ground truth must be dispatch-shaped (see learning 2).
