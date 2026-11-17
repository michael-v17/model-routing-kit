# Roadmap

## Shipped in v0.6.0

- **The agent ladder** (`agents/`) — five role agents with tier frontmatter:
  `text-and-copy-editor` (haiku), `implementer` + `visual-polish` (sonnet),
  `architecture-auditor` + `complex-implementer` (opus).
- **The dispatch ledger** (`hooks/agent-telemetry.sh`) — one JSON line per dispatch in the
  project's `.claude/routing-log.jsonl`: requested model, resolved model, tokens, duration.
  This is what makes every routing claim falsifiable — including our own evaluation.
- **Scope guard** (`hooks/scope-guard.sh`) — UI agents can never edit data adapters/stores/schemas. 18/18 tests.
- **Onboarding** (`commands/onboard.md`, `route.md`) — per-project routing map.
- **Workflows** (`workflows/`) — routed audit, mechanical migrate, probe; routing-lint keeps every
  workflow stage tier-declared.
- **Install verified live from this repo**: marketplace add → install → dispatch → ledger receipt.

## Next

1. **Decision-layer harness generalization** (`decision/`) — the `evidence/` replay runner as a
   first-class command: any candidate decider runs the three-question protocol against the same
   cases before anything gets wired. The first verdict ("safe, not saving") is in the main README.
2. **Community hardening** — the kit was born in one production setup; issue templates, an
   example project, and CI running the 72-test suite on push.

## Non-goals (on purpose)

- No subscription proxying — dispatch goes through official CLIs and their own logins, always.
- No runtime model rewriting before a replay says the decider is safe (see the main README's verdict).
