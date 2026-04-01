# flowyeah

Plan-to-PR pipeline for Claude Code. Takes any source — issues, error trackers, plan files, or conversation — and produces tested, reviewed, merged PRs with git worktree isolation.

## `flowyeah:build`

Full pipeline: source → plan → worktree → TDD → commit → PR → CI → merge.

```
flowyeah:build [from <source>] [--continuous] [--intermittent] [--on-branch <branch>]
```

| Flag | Purpose | Default |
|------|---------|---------|
| `from <source>` | Specify the input source (see table below) | Uses current conversation context |
| `--continuous` | Keep the pipeline running after merge, pick up new tasks | `false` |
| `--intermittent` | Investigate an intermittent test failure with escalating analysis (seed reproduction, shared state, bisect) | `false` |
| `--on-branch <branch>` | Target branch for PRs/MRs instead of default | Uses `git.default_branch` from config |

### Supported Sources

| Source | Example |
|--------|---------|
| GitLab issue | `flowyeah:build from gitlab:#5588` |
| GitHub issue | `flowyeah:build from github:#45` |
| Linear issue | `flowyeah:build from linear:PROJ-123` |
| Bugsink error | `flowyeah:build from bugsink:68b87507-8b6f-4250-9d5c-55a1dc39d9c6` |
| Bugsink URL | `flowyeah:build from https://bugsink.example.com/issues/issue/{id}/` |
| New Relic error | `flowyeah:build from newrelic:MXxBUE18...` |
| GitHub Actions failure | `flowyeah:build from ghactions:12345678` |
| GitHub Actions URL | `flowyeah:build from https://github.com/{owner}/{repo}/actions/runs/{run_id}/job/{job_id}` |
| Local file | `flowyeah:build from docs/plans/redesign.md` |
| Conversation | `flowyeah:build` (uses current context) |

## `flowyeah:review`

Formal code review with inline comments via platform API.

```
flowyeah:review [<number>]
```

| Argument | Purpose | Default |
|----------|---------|---------|
| `<number>` | PR/MR number to review | Auto-detected from current branch |

## `flowyeah:respond`

Address review feedback: triage, implement, reply, resolve, re-request.

```
flowyeah:respond [<number>]
```

| Argument | Purpose | Default |
|----------|---------|---------|
| `<number>` | PR/MR number to respond to | Auto-detected from current branch |

## `flowyeah:check`

Audit `flowyeah.yml` against the config schema. Takes no arguments.

Each key is annotated with a status marker:

| Marker | Meaning |
|--------|---------|
| `# ✅` | Explicitly set in file |
| `# ⬚ default: <value>` | Absent, using default |
| `# ⚠ deprecated` | Key present but deprecated |
| `# ❌ <error message>` | Validation error |

### Deprecated Keys

| Key | Removed | Migration |
|-----|---------|-----------|
| `sources` | 2026-03-02 | Remove — adapters with `source.md` are automatic |
| `hosting` | 2026-03-03 | Rename to `git_host` |
| `hooks.after_merge` | 2026-03-06 | Move to `hooks.pr.after_merge` |

## `flowyeah:status`

Project health overview: active sessions, plans, worktrees, and disk usage.

```
flowyeah:status
flowyeah:status clean
```

| Subcommand | Purpose |
|------------|---------|
| *(none)* | Read-only report of all sessions, plans, and worktrees |
| `clean` | Interactive removal of completed plans, stale artifacts, and orphaned worktrees |

## Prerequisites

- **Claude Code 1.0.33+** — verify with `claude --version`, update with `claude update`
- **git** — version control operations and worktree isolation

Depending on which adapters you use:

| Adapter | Requires |
|---------|----------|
| GitHub, GitHub Actions | [`gh`](https://cli.github.com/) (GitHub CLI) — authenticate with `gh auth login` |
| GitLab | `curl`, `jq`, and a [personal access token](https://docs.gitlab.com/ee/user/profile/personal_access_tokens.html) |
| Linear | [Claude Code Linear MCP plugin](https://github.com/anthropics/claude-code-linear) |
| Bugsink | `curl`, `jq`, and a Bugsink API token |
| New Relic | `curl`, `jq`, and a [NerdGraph API key](https://docs.newrelic.com/docs/apis/intro-apis/new-relic-api-keys/) |

## Install

Add the marketplace and install the plugin:

```
/plugin marketplace add rodrigomanhaes/flowyeah
/plugin install flowyeah@rodrigomanhaes-flowyeah
```

By default, the plugin installs at user scope (available in all projects). To install at a different scope:

```
/plugin install flowyeah@rodrigomanhaes-flowyeah --scope project  # shared via .claude/settings.json
/plugin install flowyeah@rodrigomanhaes-flowyeah --scope local    # gitignored, personal only
```

## Setup

1. Run `flowyeah:build` or `flowyeah:review` in your project — either will interactively create `flowyeah.yml` on first run
2. Commit `flowyeah.yml` to your repo

The build pipeline automatically adds `.flowyeah/` and `tmp/` to `.gitignore` when creating worktrees.

## Project Configuration

All project conventions live in `flowyeah.yml` at the project root. Run `flowyeah:check` to validate your config against the schema.

```yaml
language: en                              # Language for commits, PR titles, comments (default: en)

git:
  default_branch: main                    # Target branch for PRs (default: main)

git_host: github                          # Adapter for PR hosting (required)

testing:
  command: bundle exec rspec              # Shell command to run tests (required)
  scope: related                          # related | full (default: related)

implementation:
  brainstorm: auto                        # always | auto (default: auto)
  approval: auto                          # always | auto (default: auto)
  process_skills:
    brainstorming: null                   # Skill name or null
    planning: null                        # Skill name or null
    tdd: null                             # Skill name or null
    debugging: null                       # Skill name or null

commits:
  conventions: conventional               # conventional | freeform (default: conventional)
  writer: git-commit-writer               # Agent name or null (default: git-commit-writer)

pull_requests:
  delete_source_branch: true              # Delete branch after merge (default: true)
  rebase: true                            # Rebase before PR (default: true)
  merge: manual                           # auto | manual | ask (default: manual)
  merge_strategy: squash                  # squash | merge | rebase (default: squash)

code_review:
  agents:                                 # Review agents to run (required, non-empty)
    - pr-review-toolkit:code-reviewer
    - pr-review-toolkit:silent-failure-hunter
  optional_agents: []                     # Conditional agents based on changes (default: [])
  instructions: null                      # Relative path to review guidelines file
  evaluation_skill: null                  # Skill for evaluating respond comments

issues:
  create_when_missing: ask                # ask | always | never (default: ask)
  adapter: github                         # Adapter for issue creation (required if ask/always)

worktree:
  symlinks: []                            # Relative paths to symlink from main checkout
  env: []                                 # Per-worktree env vars [{KEY: value | auto}, ...]
  setup: []                               # Shell commands after worktree creation
  teardown: []                            # Shell commands before worktree removal

hooks:
  pr:
    after_create: null                    # Relative path to post-creation instructions
    after_merge: null                     # Relative path to post-merge instructions

adapters:
  github:                                 # Adapter-specific config (schema-free)
    # ...
```

## Adding Integrations

Each integration lives in `adapters/<name>/` with `connection.md` (required) plus any combination of:

- `source.md` — fetch data and convert to canonical plan format
- `hosting.md` — git host: create PR/MR, poll CI, merge
- `review.md` — post formal reviews with inline comments
- `respond.md` — fetch and reply to review comments

Source-only integrations (Linear, Bugsink, New Relic, GitHub Actions) only need `connection.md` + `source.md`.

Add an adapter directory, configure it in `flowyeah.yml`, and the pipeline picks it up automatically.

## Development

After cloning, install the git hooks:

```
echo '#!/bin/bash
bash "$(git rev-parse --show-toplevel)/scripts/bump-version.sh"' > .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
```

This auto-bumps the patch version in `plugin.json` and `marketplace.json` on every commit.

## Limitations

- **Single-project repos only.** One `flowyeah.yml` per project root. Monorepos with multiple apps sharing a single repo are not supported.

## License

MIT
