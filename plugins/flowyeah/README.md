# flowyeah

Plan-to-PR pipeline for Claude Code. Takes any source — issues, error trackers, plan files, or conversation — and produces tested, reviewed, merged PRs with git worktree isolation.

## Skills

| Skill | Command | What it does |
|-------|---------|--------------|
| `flowyeah:build` | `flowyeah:build [from <source>] [--continuous]` | Full pipeline: source → plan → worktree → TDD → commit → PR → CI → merge |
| `flowyeah:review` | `flowyeah:review [<pr-number>]` | Formal code review with inline comments via platform API |

## Supported Sources

| Source | Example |
|--------|---------|
| GitLab issue | `flowyeah:build from GITLAB:#5588` |
| GitHub issue | `flowyeah:build from GITHUB:#45` |
| Linear issue | `flowyeah:build from LINEAR:PROJ-123` |
| Bugsink error | `flowyeah:build from BUGSINK:45678` |
| New Relic error | `flowyeah:build from NEWRELIC:MXxBUE18...` |
| Local file | `flowyeah:build from docs/plans/redesign.md` |
| Conversation | `flowyeah:build` (uses current context) |

## Setup

1. Install the plugin in Claude Code
2. Run `flowyeah:build` or `flowyeah:review` in your project — either will interactively create `flowyeah.yml` on first run
3. Commit `flowyeah.yml` to your repo
4. Add `tmp/` to your `.gitignore` — flowyeah stores plan files in `tmp/flowyeah/plans/`

## Project Configuration

All project conventions live in `flowyeah.yml` at the project root. See the schema documentation in `skills/build/SKILL.md` for all available options.

## Adding Integrations

Each integration lives in `adapters/<name>/` with `connection.md` (required) plus any combination of:

- `source.md` — fetch data and convert to canonical plan format
- `hosting.md` — create PR/MR, poll CI, merge
- `review.md` — post formal reviews with inline comments

Source-only integrations (Linear, Bugsink, New Relic) only need `connection.md` + `source.md`.

Add an adapter directory, configure it in `flowyeah.yml`, and the pipeline picks it up automatically.

## License

MIT
