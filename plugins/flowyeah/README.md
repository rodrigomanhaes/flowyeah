# flowyeah

Plan-to-PR pipeline for Claude Code. Takes any source — issues, error trackers, plan files, or conversation — and produces tested, reviewed, merged PRs with git worktree isolation.

## Skills

| Skill | Command | What it does |
|-------|---------|--------------|
| `flowyeah:build` | `flowyeah:build [from <source>] [--continuous]` | Full pipeline: source → plan → worktree → TDD → commit → PR → CI → merge |
| `flowyeah:review` | `flowyeah:review [<pr-number>]` | Formal code review with inline comments via platform API |
| `flowyeah:respond` | `flowyeah:respond [<pr-number>]` | Address review feedback: triage, implement, reply, resolve, re-request |
| `flowyeah:check` | `flowyeah:check` | Audit `flowyeah.yml` against the config schema |

## Supported Sources

| Source | Example |
|--------|---------|
| GitLab issue | `flowyeah:build from gitlab:#5588` |
| GitHub issue | `flowyeah:build from github:#45` |
| Linear issue | `flowyeah:build from linear:PROJ-123` |
| Bugsink error | `flowyeah:build from bugsink:68b87507-8b6f-4250-9d5c-55a1dc39d9c6` |
| New Relic error | `flowyeah:build from newrelic:MXxBUE18...` |
| GitHub Actions failure | `flowyeah:build from ghactions:12345678` |
| Local file | `flowyeah:build from docs/plans/redesign.md` |
| Conversation | `flowyeah:build` (uses current context) |

## Setup

1. Install the plugin in Claude Code
2. Run `flowyeah:build` or `flowyeah:review` in your project — either will interactively create `flowyeah.yml` on first run
3. Commit `flowyeah.yml` to your repo

The build pipeline automatically adds `.flowyeah/` and `tmp/` to `.gitignore` when creating worktrees.

## Project Configuration

All project conventions live in `flowyeah.yml` at the project root. See the schema documentation in `skills/build/SKILL.md` for all available options.

The config schema evolves without versioning — deprecated keys are documented in `config-schema.md` and flagged automatically. Run `flowyeah:check` after updating the plugin to catch renamed or removed keys in your `flowyeah.yml`.

## Adding Integrations

Each integration lives in `adapters/<name>/` with `connection.md` (required) plus any combination of:

- `source.md` — fetch data and convert to canonical plan format
- `hosting.md` — git host: create PR/MR, poll CI, merge
- `review.md` — post formal reviews with inline comments

Source-only integrations (Linear, Bugsink, New Relic) only need `connection.md` + `source.md`.

Add an adapter directory, configure it in `flowyeah.yml`, and the pipeline picks it up automatically.

## Limitations

- **Single-project repos only.** One `flowyeah.yml` per project root. Monorepos with multiple apps sharing a single repo are not supported.

## License

MIT
