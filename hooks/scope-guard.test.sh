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

# --- Ticket 2: per-agent scope (differentiated built-in defaults + per-agent conf keys) ---

# Built-in differentiation (zero-config): copy-editor is text/strings only -> stylesheets are
# out of scope for it; visual-polish OWNS stylesheets.
# 11. copy-editor edits a stylesheet -> DENY (built-in style default for the copy editor)
run "copy-editor edits theme.css -> denied (style is visual-polish's job)" \
  '{"agent_type":"text-and-copy-editor","tool_name":"Edit","tool_input":{"file_path":"src/styles/theme.css"}}' DENY

# 12. visual-polish edits the same stylesheet -> ALLOW (its default is data/logic only)
run "visual-polish edits theme.css -> allowed" \
  '{"agent_type":"visual-polish","tool_name":"Edit","tool_input":{"file_path":"src/styles/theme.css"}}' ALLOW

# Per-agent conf keys: each UI agent can carry its OWN RISKY, which REPLACES the base RISKY.
PER_AGENT_PROJ="$(mktemp -d)"
mkdir -p "$PER_AGENT_PROJ/.claude"
cat > "$PER_AGENT_PROJ/.claude/scope-guard.conf" <<'EOF'
RISKY=adapter
RISKY_visual_polish=widgets
RISKY_text_and_copy_editor=onlytext
EOF

# 13. per-agent key applies: visual-polish denied on its own RISKY_visual_polish pattern
run_conf "RISKY_visual_polish denies widgets path" "$PER_AGENT_PROJ" \
  '{"agent_type":"visual-polish","tool_name":"Edit","tool_input":{"file_path":"src/widgets/Panel.tsx"}}' DENY

# 14. per-agent key REPLACES base: 'adapter' (base RISKY) is allowed for visual-polish (its key=widgets)
run_conf "per-agent key replaces base (visual-polish allowed on adapter)" "$PER_AGENT_PROJ" \
  '{"agent_type":"visual-polish","tool_name":"Edit","tool_input":{"file_path":"src/data/userAdapter.ts"}}' ALLOW

# 15. per-agent key applies: copy-editor denied on its own RISKY_text_and_copy_editor pattern
run_conf "RISKY_text_and_copy_editor denies onlytext path" "$PER_AGENT_PROJ" \
  '{"agent_type":"text-and-copy-editor","tool_name":"Edit","tool_input":{"file_path":"src/onlytext/copy.ts"}}' DENY

# 16. per-agent key REPLACES base: 'adapter' is allowed for copy-editor (its key=onlytext)
run_conf "per-agent key replaces base (copy-editor allowed on adapter)" "$PER_AGENT_PROJ" \
  '{"agent_type":"text-and-copy-editor","tool_name":"Edit","tool_input":{"file_path":"src/data/userAdapter.ts"}}' ALLOW

rm -rf "$CONF_PROJ" "$EMPTY_PROJ" "$PER_AGENT_PROJ"
