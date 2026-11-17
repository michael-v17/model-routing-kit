#!/usr/bin/env bash
# model-routing-jev: replay tier decisions (Jev 3xNoul vs Haiku 5.5) over a cases file.
#   ./run.sh <cases.jsonl> [--limit N] [--arm jev|haiku|both]
# Keys sourced from the Keychain via ../_lib/secret.sh into the python child only.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../_lib/secret.sh"
export K_JEV="$(secret jev)" K_ANTHROPIC="$(secret anthropic)"
exec python3 "$HERE/replay.py" "$@"
