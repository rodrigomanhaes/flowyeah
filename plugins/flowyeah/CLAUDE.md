# flowyeah Plugin — Developer Guide

Claude Code plugin for plan-to-PR pipelines.

## Structure

```
plugins/flowyeah/
├── skills/           # Auto-discovered by Claude Code from SKILL.md
│   ├── build/        # Main pipeline: source → plan → worktree → TDD → PR
│   └── review/       # Formal code review with inline comments
├── adapters/         # Platform integrations (shared across skills)
│   ├── gitlab/       # connection, source, sink, review
│   ├── github/       # connection, source, sink, review
│   ├── linear/       # connection, source
│   ├── bugsink/      # connection, source
│   └── newrelic/     # connection, source
├── hooks/            # Claude Code hooks for session persistence
├── setup.md          # Shared interactive config creation (used by both skills)
└── flowyeah.yml      # Generated per-project config (not in this repo)
```

## Key Conventions

- **Adapters are prose, not code.** Each `.md` file contains instructions and curl/CLI templates that Claude follows. They are NOT executed as scripts.
- **Skills reference adapters by relative path:** `adapters/<name>/connection.md` + `adapters/<name>/source.md`
- **Config schema lives in `skills/build/SKILL.md`** under "Project Configuration". Both skills share the same `flowyeah.yml` schema.
- **`setup.md`** is the single source of truth for interactive config creation. Both skills delegate to it when `flowyeah.yml` is missing.

## Testing

```bash
bash hooks/test-hooks.sh
```

Tests run in isolated temp git repos. No external dependencies beyond bash and git.

## Adding an Adapter

1. Create `adapters/<name>/connection.md` (required — auth and API conventions)
2. Add whichever roles apply: `source.md`, `sink.md`, `review.md`
3. Update the schema example in `skills/build/SKILL.md` if adding a new adapter type
4. Update `setup.md` if the adapter needs interactive config questions

## Commits

All commit messages and documentation in Portuguese (pt-BR).
