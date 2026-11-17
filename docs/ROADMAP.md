# Roadmap — what gets extracted next

The evidence layer (this repo's `evidence/`) is complete. The harness itself is being extracted
from a production setup; these are the pieces, in extraction order:

1. **The agent ladder** (`agents/`) — five role agents with tier frontmatter:
   `text-and-copy-editor` (haiku), `implementer` + `visual-polish` (sonnet),
   `architecture-auditor` + `complex-implementer` (opus). Their prompts are being scrubbed of
   environment-specific paths before shipping.
2. **The dispatch ledger** (`ledger/`) — a `routing-log.jsonl` writer (requested model, resolved
   model, tokens, duration per dispatch) + a small analyzer. This is what makes every future
   decision-layer claim falsifiable.
3. **Audit & migrate workflows** (`workflows/`) — the routed parallel audit + the mechanical
   migrate patterns (cheap implementer per file, independent verify).
4. **Decision-layer harness** (`decision/`) — the replay runner generalized: any candidate decider
   runs the same three-question protocol against the same cases before anything gets wired.

## Non-goals (on purpose)

- No subscription proxying — dispatch goes through official CLIs and their own logins, always.
- No runtime model rewriting before a replay says the decider is safe (see the main README's verdict).
