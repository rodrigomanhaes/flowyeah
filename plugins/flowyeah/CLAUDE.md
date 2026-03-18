# flowyeah Plugin — Developer Guide

Claude Code plugin for plan-to-PR pipelines.

## Structure

```
plugins/flowyeah/
├── skills/           # Auto-discovered by Claude Code from SKILL.md
│   ├── build/        # Main pipeline: source → plan → worktree → TDD → PR
│   ├── review/       # Formal code review with inline comments
│   ├── respond/     # Address review feedback on PRs/MRs
│   └── check/        # Config audit: validates flowyeah.yml against schema
├── adapters/         # Platform integrations (shared across skills)
│   ├── gitlab/       # connection, source, git host, review, respond
│   ├── github/       # connection, source, git host, review, respond
│   ├── linear/       # connection, source
│   ├── bugsink/      # connection, source
│   ├── newrelic/     # connection, source
│   └── ghactions/    # connection, source
├── hooks/            # Claude Code hooks for session persistence
├── config-schema.md  # Single source of truth for flowyeah.yml schema
├── setup.md          # Shared interactive config creation (used by all skills)
└── flowyeah.yml      # Generated per-project config (not in this repo)
```

## Key Conventions

- **Adapters are prose, not code.** Each `.md` file contains instructions and curl/CLI templates that Claude follows. They are NOT executed as scripts.
- **Skills reference adapters by relative path:** `adapters/<name>/connection.md` + `adapters/<name>/source.md`
- **Config schema lives in `config-schema.md`** at the plugin root. Build, review, setup, and check skills reference it as the single source of truth.
- **`setup.md`** is the single source of truth for interactive config creation. Both skills delegate to it when `flowyeah.yml` is missing.

## Testing

```bash
bash plugins/flowyeah/tests/test-hooks.sh
```

Tests run in isolated temp git repos. No external dependencies beyond bash and git. Currently covers hook behavior only (session injection, reminders, worktree detection). Adapter and skill consistency are validated by analysis, not automated tests. The CI pipeline (if configured) should run `bash plugins/flowyeah/tests/test-hooks.sh` as part of the test suite.

## Hook Internals

- **`${CLAUDE_PLUGIN_ROOT}`** — Claude Code sets this variable to the plugin's installation directory at runtime. The hooks use it to resolve script paths in `hooks.json`.
- **`session-inject.sh`** — injects session files on every prompt. Build sessions use `state.md` (with mission, progress, findings summary). Review sessions use `review-state-{number}.md` (namespaced by PR number, matched by current branch). Both can coexist without interference.
- **`session-remind.sh`** — nudges to update state after Edit/Write/NotebookEdit operations. Detects `state.md` (build), `review-state-*.md` (review), and `respond-state.md` (respond).

## Adding an Adapter

1. Create `adapters/<name>/connection.md` (required — auth and API conventions)
2. Add whichever roles apply: `source.md`, `hosting.md`, `review.md`, `respond.md`
3. Update `config-schema.md` if adding a new adapter type
4. Update `setup.md` if the adapter needs interactive config questions

## Commits

All commit messages and documentation in English.
