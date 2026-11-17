#!/usr/bin/env python3
"""Replay tier decisions through two arms: Jev (3 Noul, one call) and Haiku 5.5 (JSON).

Usage:  ./run.sh <cases.jsonl> [--limit N] [--arm jev|haiku|both]
  cases rows: {"id":..., "brief":..., "tier": label (optional), ...}
Output: <cases>.results.jsonl — one row per case and arm:
  {id, label, arm, h, s, o, seconds, in_tokens}
Keys arrive via env K_JEV / K_ANTHROPIC, set by run.sh (sourced secret.sh) — never in argv.
Resumable: skips (id, arm) already in the results file. No retries; stops after 5 errors.
"""
import argparse, json, os, ssl, time, urllib.request

try:
    import certifi
    _CTX = ssl.create_default_context(cafile=certifi.where())
except ImportError:
    _CTX = None

STATE_TMPL = (
    "TASK BRIEF (the prompt given to a coding subagent):\n<<<\n{brief}\n>>>\n"
    "You size coding tasks for model-tier routing. Three tiers:\n"
    "haiku = fast/cheap: single-file mechanical edits, renames, typo fixes, formatting, boilerplate.\n"
    "sonnet = mid: multi-file refactors, standard features, well-scoped changes needing real judgment.\n"
    "opus = top: subtle concurrency, architecture decisions, risky cross-cutting changes, flaky-test roots."
)
Q = {
    "haiku_ok": "Could a haiku-class tier complete this task fully, without escalating to a stronger tier?",
    "sonnet_ok": "Could a sonnet-class tier complete this task fully, without escalating?",
    "opus_ok": "Could an opus-class tier complete this task fully?",
}

def call_jev(brief):
    body = {
        "model": "jev-latest",
        "state": STATE_TMPL.format(brief=brief),
        "questions": {k: {"type": "noul", "instructions": q} for k, q in Q.items()},
    }
    req = urllib.request.Request(
        "https://api.typesafe.ai/v1/systemone",
        data=json.dumps(body).encode(),
        headers={"Authorization": "Bearer " + os.environ["K_JEV"],
                 "Content-Type": "application/json"})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=30, context=_CTX) as r:
        out = json.load(r)
    a = out["answers"]
    return {"h": a["haiku_ok"]["noul"], "s": a["sonnet_ok"]["noul"], "o": a["opus_ok"]["noul"],
            "seconds": round(time.time() - t0, 3), "in_tokens": out.get("usage", {}).get("input_tokens", 0)}

def call_haiku(brief):
    schema = {"type": "object", "additionalProperties": False,
              "required": ["haiku_ok", "sonnet_ok", "opus_ok"],
              "properties": {k: {"type": "number"} for k in ("haiku_ok", "sonnet_ok", "opus_ok")}}
    body = {
        "model": "claude-haiku-5-5", "max_tokens": 200,
        "thinking": {"type": "disabled"},
        "output_config": {"effort": "low", "format": {"type": "json_schema", "schema": schema}},
        "messages": [{"role": "user", "content":
            STATE_TMPL.format(brief=brief) +
            "\nAnswer with three probabilities (0.0-1.0), one per question, as JSON."}],
    }
    req = urllib.request.Request(
        "https://api.anthropic.com/v1/messages",
        data=json.dumps(body).encode(),
        headers={"x-api-key": os.environ["K_ANTHROPIC"],
                 "anthropic-version": "2023-06-01",
                 "content-type": "application/json"})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=30, context=_CTX) as r:
        out = json.load(r)
    o = json.loads(out["content"][0]["text"])
    return {"h": o["haiku_ok"], "s": o["sonnet_ok"], "o": o["opus_ok"],
            "seconds": round(time.time() - t0, 3),
            "in_tokens": out.get("usage", {}).get("input_tokens", 0)}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cases")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--arm", choices=("jev", "haiku", "both"), default="both")
    args = ap.parse_args()
    res_path = os.path.splitext(args.cases)[0] + ".results.jsonl"
    done = set()
    if os.path.exists(res_path):
        for l in open(res_path, encoding="utf-8"):
            try:
                r = json.loads(l)
                done.add((r["id"], r["arm"]))
            except Exception:
                pass
    rows = [json.loads(l) for l in open(args.cases, encoding="utf-8") if l.strip()]
    if args.limit:
        rows = rows[: args.limit]
    out = open(res_path, "a", encoding="utf-8")
    n_err = 0
    for row in rows:
        brief = row["brief"][:4000]
        arms = ("jev", "haiku") if args.arm == "both" else (args.arm,)
        for arm in arms:
            if (row["id"], arm) in done:
                continue
            try:
                r = call_jev(brief) if arm == "jev" else call_haiku(brief)
                rec = {"id": row["id"], "label": row.get("tier"), "arm": arm, **r}
                out.write(json.dumps(rec, ensure_ascii=False) + "\n"); out.flush()
                print(f"{arm:6s} {row['id']:24s} h={r['h']:.2f} s={r['s']:.2f} o={r['o']:.2f} "
                      f"{r['seconds']}s {r['in_tokens']}tk", flush=True)
            except Exception as e:
                n_err += 1
                print(f"{arm:6s} {row['id']:24s} ERROR {type(e).__name__}: {str(e)[:120]}", flush=True)
                if n_err >= 5:
                    raise SystemExit(f"stopping: {n_err} errors")
    out.close()
    print(f"done -> {res_path}")

if __name__ == "__main__":
    main()
