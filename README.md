# flowyeah

Plan-to-PR pipeline for Claude Code. Takes any source — issues, error trackers, plan files, or conversation — and produces tested, reviewed, merged PRs with git worktree isolation.

## Install

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

## Use Cases

### Implement an issue from a tracker

Point `flowyeah:build` at any issue and it drives the full cycle: fetch the issue, generate a plan, create a worktree, implement with TDD, open a PR, wait for CI and code review, and merge.

```
flowyeah:build from github:#45
flowyeah:build from gitlab:#5588
flowyeah:build from linear:PROJ-123
```

**What happens:**

1. Fetches the issue and extracts requirements into a task plan
2. Creates an isolated git worktree and claims the issue in the tracker
3. Picks the first task — brainstorms approach if the task is complex
4. Implements via TDD: write a failing test, make it pass, refactor
5. Commits, runs the test suite, and pushes
6. Opens a PR linking back to the issue
7. Runs code review agents in parallel and waits for CI
8. If CI or review finds problems, fixes and re-pushes (up to 3 CI attempts before asking for help)
9. Merges (or stops and asks, depending on your `pull_requests.merge` setting)
10. Cleans up the worktree

### Fix a production error

Feed an error tracker URL or ID directly. The pipeline fetches the error details, stack trace, and context, then follows the same build cycle.

```
flowyeah:build from bugsink:68b87507-8b6f-4250-9d5c-55a1dc39d9c6
flowyeah:build from https://bugsink.example.com/issues/issue/{id}/
flowyeah:build from newrelic:MXxBUE18...
```

### Fix a CI failure

Point at a failing GitHub Actions run. The pipeline fetches the failure log, identifies the root cause, and builds a fix.

```
flowyeah:build from ghactions:12345678
flowyeah:build from https://github.com/{owner}/{repo}/actions/runs/{run_id}/job/{job_id}
```

### Investigate an intermittent test failure

When a CI failure looks non-deterministic, `--intermittent` runs an escalating investigation from a clean main branch — independent of the PR that triggered the failure.

```
flowyeah:build from ghactions:12345678 --intermittent
```

**What happens:**

1. Creates a worktree from **main** (not the PR branch)
2. Runs the failing test in isolation
3. Reproduces with the CI seed to match test ordering
4. Analyzes shared state: database leaks, globals, time dependencies
5. Runs framework-specific bisect (`rspec --bisect`, `pytest`, `jest`)
6. If root cause found, switches to the normal TDD fix cycle
7. If not reproducible on main, stops and reports — the flakiness may be PR-specific

### Build from a plan or conversation

No tracker needed. Describe what you want in the conversation, or point at a local plan file.

```
flowyeah:build from docs/plans/redesign.md
flowyeah:build
```

When invoked without `from`, the pipeline uses the current conversation context as the source.

### Work through a multi-task plan without stopping

`--continuous` keeps the pipeline running after each merge, picking up the next unchecked task from the plan until everything is done.

```
flowyeah:build from github:#45 --continuous
```

The pipeline stops if it hits an ambiguous task that needs clarification or 3 consecutive CI failures.

### Resume work on an existing branch

`--on-branch` attaches to an existing branch instead of creating a new one. Useful for picking up where a previous session left off.

```
flowyeah:build --on-branch feat/webhook-v2
```

Skips branch creation, issue claiming, and status transitions. Reuses the existing worktree if one exists for that branch.

### Review a pull request

`flowyeah:review` runs code review agents in parallel, validates requirements against the linked issue, and submits a formal review with inline comments.

```
flowyeah:review 42
flowyeah:review          # auto-detects PR from current branch
```

**What happens:**

1. Gathers context: diff, commit history, CLAUDE.md rules, git blame, previous review comments
2. Launches all review agents from `code_review.agents` in parallel
3. Runs critical checks: DB concurrency, API compatibility, naming consistency
4. Consolidates findings, removes duplicates, sorts by severity
5. Presents each finding interactively — you approve, filter by severity, or edit before submission
6. You choose the review type: Request Changes, Comment, or Approve
7. Submits the review with inline comments to the PR

### Self-review before submitting

`--own` runs the full review pipeline but does not submit to the PR. Useful for catching issues before asking for a human review.

```
flowyeah:review --own 42
```

After showing findings, you choose:
- **Fix now** — fix manually, then `flowyeah:review finalize 42`
- **Delegate** — hand off to `flowyeah:respond --own 42` for automated fixes
- **Finalize** — clean up immediately

You can run multiple `--own` rounds before finalizing.

### Address review feedback on a PR

`flowyeah:respond` fetches unresolved review comments, lets you triage each one, implements fixes, replies to threads, and re-requests review.

```
flowyeah:respond 42
flowyeah:respond         # auto-detects PR from current branch
```

**What happens:**

1. Fetches all unresolved review threads, grouped by reviewer
2. Evaluates each comment (if `code_review.evaluation_skill` is configured): agree, disagree, or needs clarification
3. You triage each finding interactively:
   - **`i`** — implement the fix
   - **`r`** — reject (disagree with the finding)
   - **`d`** — discuss further (back-and-forth with the evaluation skill)
   - **`s`** — reply directly to the reviewer thread
4. Sets up a worktree, implements all accepted fixes via TDD
5. Pushes, replies to each thread with what was done, resolves conversations
6. Re-requests review from all reviewers (new commits invalidate prior approvals)

### Implement fixes from a self-review

`flowyeah:respond --own` addresses findings from a prior `flowyeah:review --own` session. Same triage and implementation flow, but no thread replies or review re-requests since there are no external reviewers.

```
flowyeah:respond --own 42
```

After completion, you can run another `flowyeah:review --own` round or finalize.

### Validate your configuration

`flowyeah:check` audits `flowyeah.yml` against the config schema. No arguments, no mutations — read-only.

```
flowyeah:check
```

Shows every key annotated with a status marker:

| Marker | Meaning |
|--------|---------|
| `# ✅` | Explicitly set in file |
| `# ⬚ default: <value>` | Absent, using default |
| `# ⚠ deprecated` | Key present but deprecated |
| `# ❌ <error message>` | Validation error |

Ends with a summary of errors, warnings, and optional keys with their defaults.

### See what's active and clean up

`flowyeah:status` shows all active sessions, plans, worktrees, and disk usage.

```
flowyeah:status
```

Add `clean` for interactive removal of completed plans, stale artifacts, and orphaned worktrees:

```
flowyeah:status clean
```

Each category is presented separately — you confirm or skip before anything is removed.

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
