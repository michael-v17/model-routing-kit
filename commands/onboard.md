Analyze THIS project and propose a token-efficient model-routing setup. Do NOT edit yet — return a plan.

1. Project type: detect from package.json / config — Next.js, Vite, CRA, React Native, Vue, Svelte, Astro, plain web, or full-stack.
2. UI surfaces: where do screens/pages/components live (app/, src/pages, src/components, screens/)?
3. Styles: Tailwind config? CSS modules? styled-components? sass? Where do design tokens live?
4. Business logic & data: where are data adapters, API clients, stores (redux/zustand/pinia), persistence, schemas, fixtures, hooks, services?
5. Commands: dev, build, test, lint, typecheck, e2e — read them from package.json scripts.
6. Tooling: Playwright? a frontend design plugin? MCP servers? Storybook?
7. Risky-path patterns: from (4), produce a project-specific regex for the scope-guard (RISKY=...). Frontend default: adapter|persistence|store|schema|migration|fixture|/api/|\.sql — add this project's real folder names (e.g. src/services, src/data, prisma/).
8. Routing map: which folders/globs map to text-and-copy-editor / visual-polish / complex-implementer / architecture-auditor. Flag any hard surfaces (complex animations, canvas/WebGL/particles, perf-sensitive rendering, intricate algorithms) that warrant complex-implementer (opus/high). Note which tasks should just use the built-in Explore (read-only) or opusplan (planning).
9. Output: a CLAUDE.md routing block (from CLAUDE.template.md) filled in for this project, plus the tuned RISKY pattern for hooks/scope-guard.sh. Return the plan; ask before writing.
