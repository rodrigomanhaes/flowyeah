# flowyeah Plugin — Developer Guide

Claude Code plugin for plan-to-PR pipelines.

## Structure

```
plugins/flowyeah/
├── skills/           # Auto-discovered by Claude Code from SKILL.md
│   ├── build/        # Main pipeline: source → plan → worktree → TDD → PR
│   ├── review/       # Formal code review with inline comments
│   ├── respond/     # Address review feedback on PRs/MRs
│   ├── check/        # Config audit: validates flowyeah.yml against schema
│   └── status/       # Project health: sessions, plans, worktrees, cleanup
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

## Critical: Edit Source, Not Installed Copy

When editing plugin files (skills, adapters, hooks, config schema), always edit the files in the current working directory — this is the source repo. NEVER edit the locally installed copy that Claude Code uses at runtime. The Skill tool loads content from the installed copy, but that path is NOT where edits belong.

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
- **`session-inject.sh`** — injects session files on every prompt. Build sessions use `state.md` (with mission, progress, findings summary). Review and respond sessions use `review-state-{N}.md` and `respond-state-{N}.md` (namespaced by PR number); every active state file is injected with a PR-labeled header (`flowyeah:review session (PR #N, branch X)`) so the agent can disambiguate when several PRs are in flight. No branch-based filtering happens at injection — the skills' `--own` flows run from the primary checkout on a branch that doesn't match the PR source, so filtering would silently hide active sessions. When an `--own` review round has produced rejections, an additional `Previously rejected: N` count line points the model at `own-rejections-{N}.md`. Build, review, and respond sessions can coexist without interference.
- **`session-remind.sh`** — nudges to update state after Edit/Write/NotebookEdit operations. Detects `state.md` (build), `review-state-*.md` (review), and `respond-state-*.md` (respond).
- **`tree-guard.sh`** — PreToolUse hook on `Bash`. Blocks tree-mutating git commands (`checkout`, `checkout-index`, `restore`, `switch`, `reset`, `apply`, `am`, `merge`, `rebase`, `pull`, `stash`, `clean`, `cherry-pick`, `revert`, `rm`, `mv`, `bisect` — including `git -C`/`--git-dir=` forms; `stash list|show` and `clean` dry-runs pass) when invoked from the primary checkout while a flowyeah review or respond session is active for the current branch. Detection signals, in precedence order: (1) `review-state-{N}.md` matches the current branch; (2) `respond-state-{N}.md` matches the current branch. Review sessions in phases where the pipeline is inactive and the user is sanctioned to work on the branch (`Fixing`, `Delegated`, `Responded`) do not block. Build sessions are intentionally out of scope — build pipelines run isolated inside `.flowyeah/worktrees/{name}/` on branches git prevents the primary from sharing, so the primary checkout stays free for unrelated work (deploys, hotfixes, rebases on stable branches); the build agent enforces its own "primary untouched" discipline from inside the worktree (see `skills/build/SKILL.md`). Stays out of the way inside any worktree under `.flowyeah/worktrees/` or `.flowyeah/review-worktrees/`, in non-flowyeah projects, and on read-only commands like `git fetch`/`git show`/`git blame`. Enforces the "Invariant: Primary Checkout Is Untouched" rule documented in `skills/review/SKILL.md` and `skills/respond/SKILL.md`. The error message names the active session via a session-specific descriptor and points at the right worktree path / exit command. Exits 2 with stderr to block, 0 to allow; never errors out (a hook bug must not lock the user out).

## Adding an Adapter

1. Create `adapters/<name>/connection.md` (required — auth and API conventions)
2. Add whichever roles apply: `source.md`, `hosting.md`, `review.md`, `respond.md`
3. If the adapter has config keys, create `adapters/<name>/config-schema.md` declaring them (see an existing one, e.g. `adapters/bugsink/config-schema.md`). Adding or renaming any adapter key later means updating this file too, or `flowyeah:check` will flag it as an unknown key.
4. Update `config-schema.md` (root) if adding a new adapter type
5. Update `setup.md` if the adapter needs interactive config questions

## Commits

All commit messages and documentation in English.
