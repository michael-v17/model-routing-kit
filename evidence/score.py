#!/usr/bin/env python3
"""Score the tier-decider replay: threshold sweep, cost-quality frontier, canary check, verdict.

Pre-registered criteria (README, before any full run):
  (i)  >=85% agreement on stratified SWE-bench OR frontier parity with always-sonnet at lower cost;
  (ii) 0 under-routing on the 43 real canaries at the chosen threshold;
  (iii) decision cost <$0.001 and p95 latency <1s.
Cost index: list price in USD per 1M output tokens for Haiku 5.5 · Sonnet 5.5 · Opus 5.5
(Anthropic's pricing page, October 2026): haiku 0.5 · sonnet 10 · opus 20. Equal tokens per task
are assumed, so "cost/task" is a relative index across tiers, not dollars spent.
"""
import json, statistics, sys

TIERS = ("haiku", "sonnet", "opus")
PRICE = {"haiku": 0.5, "sonnet": 10.0, "opus": 20.0}

def load(path):
    rows = [json.loads(l) for l in open(path) if l.strip()]
    by = {}
    for r in rows:
        by.setdefault(r["arm"], {})[r["id"]] = r
    return by

def decide(r, thr):
    probs = {"haiku": r["h"], "sonnet": r["s"], "opus": r["o"]}
    for t in TIERS:
        if probs[t] >= thr:
            return t
    return "opus"  # nothing clears the bar -> conservative escalation

def sweep(by, labels):
    print(f"{'thr':>4} | {'arm':6} | {'agree':>5} | {'under':>5} | {'over':>5} | {'solved':>6} | {'cost/task':>9}")
    best = {}
    for thr in (0.5, 0.6, 0.7, 0.8, 0.9):
        for arm, cases in by.items():
            ag = un = ov = 0; solved = 0; cost = 0.0; n = 0
            for cid, r in cases.items():
                lab = labels.get(cid)
                if lab not in TIERS: continue
                ch = decide(r, thr); n += 1
                if ch == lab: ag += 1
                elif TIERS.index(ch) < TIERS.index(lab): un += 1
                else: ov += 1
                if TIERS.index(ch) >= TIERS.index(lab):
                    solved += 1; cost += PRICE[ch]
                else:  # too cheap: task fails, rerun at label price
                    solved += 0; cost += PRICE[ch] + PRICE[lab]
            if n:
                print(f"{thr:4.2f} | {arm:6} | {100*ag//n:4d}% | {100*un//n:4d}% | {100*ov//n:4d}% | {100*solved//n:4d}% | {cost/n:9.3f}")
                key = (arm, thr)
                best.setdefault(arm, []).append((cost / n, 100 * solved / n, 100 * ag / n, 100 * un / n))
    return best

def baselines(labels):
    labs = [v for v in labels.values() if v in TIERS]
    n = len(labs)
    for t in TIERS:
        solved = sum(1 for l in labs if TIERS.index(t) >= TIERS.index(l))
        print(f"  always-{t:6s}: solved {100*solved//n}% · cost/task {PRICE[t]:.3f}")

def canaries(path):
    # The canary briefs (cases-canary.jsonl) come from private repositories and are withheld;
    # each results row carries its own tier in "label", so the check needs only the results file.
    res = load(path)
    print("\nCANARY (43 real opus reviews — under-routing must be 0 at the chosen threshold):")
    for thr in (0.5, 0.6, 0.7, 0.8, 0.9):
        for arm, cases in res.items():
            un = sum(1 for r in cases.values()
                     if TIERS.index(decide(r, thr)) < TIERS.index(r["label"]))
            print(f"  thr {thr:.2f} {arm:6}: under-routed {un}/{len(cases)}")

def stats(path, name):
    res = load(path)
    print(f"\n{name} — per-decision stats:")
    for arm, cases in res.items():
        secs = sorted(r["seconds"] for r in cases.values())
        tks = [r["in_tokens"] for r in cases.values()]
        p95 = secs[min(int(0.95 * len(secs)), len(secs) - 1)]
        per_call = 0.042 * statistics.mean(tks) / 1e6 if arm == "jev" else None
        print(f"  {arm:6}: n={len(cases)} · p50 {secs[len(secs)//2]:.2f}s p95 {p95:.2f}s · "
              f"~{statistics.mean(tks):.0f} tk/decision" + (f" · ${per_call:.6f}" if per_call else ""))

def main():
    sw = load("cases-swebench.results.jsonl")
    labels = {json.loads(l)["id"]: json.loads(l)["tier"] for l in open("cases-swebench.jsonl")}
    print("SWE-BENCH VERIFIED stratified (72) — sweep:")
    sweep(sw, labels)
    print("\nBaselines (same set):")
    baselines(labels)
    canaries("cases-canary.results.jsonl")
    stats("cases-swebench.results.jsonl", "SWE-bench")
    stats("cases-canary.results.jsonl", "Canaries")

if __name__ == "__main__":
    main()
