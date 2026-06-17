#!/usr/bin/env bash
# Drives scope-guard.sh against fixtures and prints a pass/fail table.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
GUARD="$DIR/scope-guard.sh"

run() {
  local name="$1" payload="$2" expect="$3"
  out="$(printf '%s' "$payload" | bash "$GUARD")"
  if printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then got=DENY; else got=ALLOW; fi
  if [ "$got" = "$expect" ]; then status="PASS"; else status="FAIL"; fi
  printf '%-6s | expect %-5s got %-5s | %s\n' "$status" "$expect" "$got" "$name"
}

# run_conf: like run, but points the guard at a project dir (CLAUDE_PROJECT_DIR) whose
# .claude/scope-guard.conf supplies the RISKY pattern. Proves Ticket 1 (config-driven RISKY).
run_conf() {
  local name="$1" projdir="$2" payload="$3" expect="$4"
  out="$(printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$projdir" bash "$GUARD")"
  if printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then got=DENY; else got=ALLOW; fi
  if [ "$got" = "$expect" ]; then status="PASS"; else status="FAIL"; fi
  printf '%-6s | expect %-5s got %-5s | %s\n' "$status" "$expect" "$got" "$name"
}

# 1. visual-polish edits a CSS file -> ALLOW
run "visual-polish edits Button.css" \
  '{"agent_type":"visual-polish","tool_name":"Edit","tool_input":{"file_path":"src/components/Button.css"}}' ALLOW

# 2. visual-polish edits a data adapter -> DENY
run "visual-polish edits userAdapter.ts" \
  '{"agent_type":"visual-polish","tool_name":"Edit","tool_input":{"file_path":"src/data/userAdapter.ts"}}' DENY

# 3. text-and-copy-editor edits a schema -> DENY
run "copy-editor edits schema.prisma" \
  '{"agent_type":"text-and-copy-editor","tool_name":"Edit","tool_input":{"file_path":"prisma/schema.prisma"}}' DENY

# 4. visual-polish sneaks via Bash sed on a store -> DENY (Bash path covered)
run "visual-polish bash-edits store via sed" \
  '{"agent_type":"visual-polish","tool_name":"Bash","tool_input":{"command":"sed -i s/x/y/ src/state/cartStore.ts"}}' DENY

# 5. web-implementer (not UI-only) edits an adapter -> ALLOW (allowed to touch data)
run "web-implementer edits adapter" \
  '{"agent_type":"web-implementer","tool_name":"Edit","tool_input":{"file_path":"src/data/userAdapter.ts"}}' ALLOW

# 6. main session edits anything -> ALLOW
run "main edits migration" \
  '{"agent_type":"main","tool_name":"Edit","tool_input":{"file_path":"db/migration_001.sql"}}' ALLOW

# 7. copy-editor edits a normal label file -> ALLOW
run "copy-editor edits en.json" \
  '{"agent_type":"text-and-copy-editor","tool_name":"Edit","tool_input":{"file_path":"locales/en.json"}}' ALLOW

# --- Ticket 1: RISKY read from .claude/scope-guard.conf (key=value), with default fallback ---

# A project whose conf defines a project-specific RISKY (key=value form).
CONF_PROJ="$(mktemp -d)"
mkdir -p "$CONF_PROJ/.claude"
cat > "$CONF_PROJ/.claude/scope-guard.conf" <<'EOF'
# scope-guard config for this project (full-line comments + blanks ignored)

RISKY=legacy|payments
EOF

# A project whose conf is comment/blank only -> no RISKY value -> falls back to the default.
EMPTY_PROJ="$(mktemp -d)"
mkdir -p "$EMPTY_PROJ/.claude"
cat > "$EMPTY_PROJ/.claude/scope-guard.conf" <<'EOF'
# intentionally defines nothing
EOF

# 8. conf RISKY matches a project-specific path the DEFAULT would miss -> DENY
run_conf "conf RISKY denies src/legacy/payments.ts" "$CONF_PROJ" \
  '{"agent_type":"visual-polish","tool_name":"Edit","tool_input":{"file_path":"src/legacy/payments.ts"}}' DENY

# 9. conf REPLACES the default: an 'adapter' path (default-risky) is allowed under this conf -> ALLOW
run_conf "conf replaces default (adapter now allowed)" "$CONF_PROJ" \
  '{"agent_type":"visual-polish","tool_name":"Edit","tool_input":{"file_path":"src/data/userAdapter.ts"}}' ALLOW

# 10. comment-only conf -> default pattern still applies -> DENY on an adapter path
run_conf "empty conf falls back to default (adapter denied)" "$EMPTY_PROJ" \
  '{"agent_type":"visual-polish","tool_name":"Edit","tool_input":{"file_path":"src/data/userAdapter.ts"}}' DENY

rm -rf "$CONF_PROJ" "$EMPTY_PROJ"
