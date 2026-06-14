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
