#!/usr/bin/env bash
# Tests for the PostToolUse Agent telemetry hook (Ticket 4, cost half).
#
# Covers:
#   1. a completed Agent call appends one JSONL line with the usage fields
#   2. requested == resolved            -> model_mismatch false
#   3. requested != resolved            -> model_mismatch TRUE (the silent-override detector)
#   4. no explicit model on the call    -> expected tier read from the kit agent's frontmatter
#   5. namespace-prefixed agentType     -> logged as the bare name
#   6. a non-Agent tool                 -> nothing logged (hook stays out of the way)
#   7. malformed / empty payload        -> exits 0 and logs nothing (never breaks a session)
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
HOOK="$DIR/agent-telemetry.sh"
pass=0 fail=0
ok()  { printf 'PASS   | %s\n' "$1"; pass=$((pass+1)); }
bad() { printf 'FAIL   | %s\n' "$1"; fail=$((fail+1)); }

if ! command -v jq >/dev/null 2>&1; then
  printf 'SKIP   | jq absent — telemetry hook is a no-op without it\n----\n0 passed, 0 failed\n'
  exit 0
fi

# Each case runs in a throwaway project dir so the ledger starts empty.
# Runs the hook in a throwaway project dir. Echoes the last logged line (empty if none).
# Exit code is checked separately by run_hook_rc — a command substitution runs in a subshell,
# so a variable set here would not survive back to the caller.
run_hook() { # payload -> echoes the last logged line (empty if none)
  local payload="$1" proj
  proj="$(mktemp -d)"
  printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$proj" CLAUDE_PLUGIN_ROOT="$ROOT" bash "$HOOK" >/dev/null 2>&1
  if [ -f "$proj/.claude/routing-log.jsonl" ]; then tail -n1 "$proj/.claude/routing-log.jsonl"; fi
  rm -rf "$proj"
}

run_hook_rc() { # payload -> returns the hook's exit code
  local payload="$1" proj rc
  proj="$(mktemp -d)"
  printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$proj" CLAUDE_PLUGIN_ROOT="$ROOT" bash "$HOOK" >/dev/null 2>&1
  rc=$?
  rm -rf "$proj"
  return $rc
}

completed_payload() { # subagent_type, model (may be ""), resolvedModel
  jq -nc --arg st "$1" --arg m "$2" --arg rm "$3" \
    '{ tool_name: "Agent",
       tool_input: ({ subagent_type: $st, description: "do a thing" }
                    + (if $m == "" then {} else { model: $m } end)),
       tool_response: { status: "completed", agentId: "abc123", resolvedModel: $rm,
                        totalTokens: 12450, totalDurationMs: 48211, totalToolUseCount: 7,
                        usage: { input_tokens: 8320, output_tokens: 410,
                                 cache_read_input_tokens: 3600, cache_creation_input_tokens: 120 } } }'
}

# 1. a completed Agent call is logged with its usage fields
line="$(run_hook "$(completed_payload implementer sonnet claude-sonnet-4-5)")"
if [ -n "$line" ] \
   && [ "$(printf '%s' "$line" | jq -r '.source')" = "agent" ] \
   && [ "$(printf '%s' "$line" | jq -r '.agent')" = "implementer" ] \
   && [ "$(printf '%s' "$line" | jq -r '.total_tokens')" = "12450" ] \
   && [ "$(printf '%s' "$line" | jq -r '.cache_read_tokens')" = "3600" ] \
   && [ "$(printf '%s' "$line" | jq -r '.tool_use_count')" = "7" ]; then
  ok "completed Agent call logs one line with usage telemetry"
else bad "completed Agent call did not log the expected usage fields (got: $line)"; fi

# 2. requested matches resolved -> no mismatch
line="$(run_hook "$(completed_payload implementer sonnet claude-sonnet-4-5)")"
if [ "$(printf '%s' "$line" | jq -r '.model_mismatch')" = "false" ]; then
  ok "requested == resolved -> model_mismatch false"
else bad "expected model_mismatch false (got: $line)"; fi

# 3. requested does NOT match resolved -> the detector fires.
#    This is the CLAUDE_CODE_SUBAGENT_MODEL / availableModels / fallback case: the kit asked
#    for opus, something silently ran haiku, and nothing else in the kit would notice.
line="$(run_hook "$(completed_payload architecture-auditor opus claude-haiku-4-5)")"
if [ "$(printf '%s' "$line" | jq -r '.model_mismatch')" = "true" ] \
   && [ "$(printf '%s' "$line" | jq -r '.requested_model')" = "opus" ] \
   && [ "$(printf '%s' "$line" | jq -r '.resolved_model')" = "claude-haiku-4-5" ]; then
  ok "requested != resolved -> model_mismatch TRUE (silent-override detector)"
else bad "expected model_mismatch true for opus->haiku (got: $line)"; fi

# 4. no explicit model -> expected tier comes from the kit agent's frontmatter.
#    architecture-auditor is model: opus, so a haiku run must still register as a mismatch.
line="$(run_hook "$(completed_payload architecture-auditor "" claude-haiku-4-5)")"
if [ "$(printf '%s' "$line" | jq -r '.requested_model')" = "opus" ] \
   && [ "$(printf '%s' "$line" | jq -r '.model_mismatch')" = "true" ]; then
  ok "no explicit model -> expected tier read from agents/*.md frontmatter"
else bad "frontmatter fallback did not resolve architecture-auditor to opus (got: $line)"; fi

# 5. namespace-prefixed dispatch is logged under the bare agent name
line="$(run_hook "$(completed_payload model-routing-kit:visual-polish sonnet claude-sonnet-4-5)")"
if [ "$(printf '%s' "$line" | jq -r '.agent')" = "visual-polish" ]; then
  ok "namespace-prefixed agentType logged as bare name"
else bad "namespace prefix not stripped (got: $line)"; fi

# 6. a non-Agent tool logs nothing
line="$(run_hook '{"tool_name":"Edit","tool_input":{"file_path":"a.ts"},"tool_response":{}}')"
if [ -z "$line" ]; then ok "non-Agent tool logs nothing"; else bad "logged for a non-Agent tool (got: $line)"; fi

# 7. malformed and empty payloads exit 0 without logging (telemetry never breaks a session)
line="$(run_hook 'not json at all')"
line2="$(run_hook '')"
run_hook_rc 'not json at all'; rc_bad=$?
run_hook_rc '';               rc_empty=$?
if [ -z "$line" ] && [ -z "$line2" ] && [ "$rc_bad" -eq 0 ] && [ "$rc_empty" -eq 0 ]; then
  ok "malformed/empty payload exits 0 and logs nothing"
else bad "malformed/empty payload misbehaved (rc=$rc_bad/$rc_empty, got: $line$line2)"; fi

printf -- '----\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
