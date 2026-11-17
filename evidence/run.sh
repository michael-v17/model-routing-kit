#!/usr/bin/env bash
# model-routing-jev: replay tier decisions (Jev 3xNoul vs Haiku 5.5) over a cases file.
#   ./run.sh <cases.jsonl> [--limit N] [--arm jev|haiku|both]
# Provide keys via env (never argv): K_JEV and K_ANTHROPIC. Export them from your own secret store.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
: "${K_JEV:?export K_JEV first}" "${K_ANTHROPIC:?export K_ANTHROPIC first}"

exec python3 "$HERE/replay.py" "$@"
