# flowyeah.yml Interactive Setup

Shared setup instructions used by `flowyeah:build`, `flowyeah:review`, and `flowyeah:respond` when `flowyeah.yml` is missing, and by `flowyeah:check` via Reconcile Mode.

## When to Run

If `flowyeah.yml` does not exist in the project root, run this interactive setup before proceeding.

## Schema Reference

Valid keys, types, defaults, and allowed values are defined in `config-schema.md` at the plugin root. This setup asks questions to populate those keys.

## Questions

Ask each question in order. Use sensible defaults based on the project context.

### 1. Git host

> Where do you create PRs/MRs?

Detect from `git remote get-url origin`:
- Contains `github.com` → suggest `github`
- Contains `gitlab` → suggest `gitlab`
- Otherwise → ask

### 2. Adapters

> Which integrations do you use for issues/errors?

Options (multi-select):
- **gitlab** — GitLab issues
- **github** — GitHub issues
- **linear** — Linear issues (requires MCP plugin)
- **bugsink** — Bugsink errors (requires API token)
- **newrelic** — New Relic errors (requires API key)
- **ghactions** — GitHub Actions CI logs (requires `gh` CLI)

Default: include the git host. When `github` is selected as git host or as an adapter, suggest also enabling `ghactions`.

Any adapter with a `source.md` file is automatically available as a source — no separate list needed.

### 3. Adapter config

For each selected adapter, ask for required config:

| Adapter | Questions |
|---------|-----------|
| `gitlab` | URL, token env var name, token source file, project ID |
| `github` | (none — uses `gh` CLI) |
| `linear` | Status transition on start (`on_start`), team for issue creation |
| `bugsink` | URL, token env var name, token source file, resolve/comment on merge (`on_merge`) |
| `newrelic` | Token env var name, token source file, account ID |
| `ghactions` | (none — uses `gh` CLI, same as GitHub) |

**If the user selected `linear`:**

> Should Linear issues automatically change status when you start working on them?

Options: **Yes** (default), **No**

If **Yes**:

> What Linear status should issues move to when you start working?

Default: `In Progress`

> Should this happen automatically, or should the pipeline ask first?

Options: `always` (default), `ask`

If configured, add to `flowyeah.yml`:
```yaml
adapters:
  linear:
    on_start:
      status: <answer>
      mode: <answer>
```

If **No**: skip, don't add the `on_start` key.

**If the user selected `bugsink`:**

> When flowyeah merges a fix for a Bugsink error, should it resolve the issue?

Options: `always` (default), `ask`, `never`

Resolution uses Bugsink's "resolved by the next release" (`resolve-next/`), since
at merge time the fix is not yet deployed. This needs releases configured — the
SDK must attach a `release` identifier to events. Without releases the resolution
degrades toward a plain resolve (reopens on the next event from the old code). If
the project doesn't use releases, prefer `never` or `ask`.

> Should flowyeah post a traceability comment (MR/PR link, issue, solution, branch) on merge?

Options: **Yes** (default), **No**

If resolve is not `never` or the comment is **Yes**, add to `flowyeah.yml`:
```yaml
adapters:
  bugsink:
    on_merge:
      resolve: <answer>   # always | ask | never
      comment: <always if Yes, never if No>
```

If resolve is `never` and the comment is **No**: skip, don't add the `on_merge` key.

### 4. Default branch

> What is your default branch?

Detect: `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@'`

Fallback: `main`

### 5. Test command

> What command runs your tests?

Detect from project files:
- `Gemfile` → suggest `bundle exec rspec`
- `package.json` with `test` script → suggest `npm test` or `yarn test`
- `Cargo.toml` → suggest `cargo test`
- Otherwise → ask

### 6. Test scope

> Run full suite or only related tests?

Options: `related` (default), `full`

### 7. Brainstorming

> Always brainstorm before implementing, or let AI decide?

Options: `always`, `auto` (default)

- **`always`** — every task goes through brainstorm → plan → TDD. Recommended for legacy, large, or critical codebases where even small changes need discussion.
- **`auto`** — AI assesses complexity: trivial tasks skip brainstorming, non-trivial tasks get the full cycle. Recommended for greenfield projects.

### 8. Implementation approval

> Approve implementation before pushing, or let AI decide?

Options: `always`, `auto` (default)

- **`always`** — present the implementation for developer approval before pushing. Recommended for legacy, large, or critical codebases where every change needs human review before leaving the local environment.
- **`auto`** — AI assesses risk: straightforward changes push automatically, complex or high-risk changes ask. Recommended for greenfield projects.

### 9. Process skills

> Do you use process skills for brainstorming, planning, TDD, or debugging?

Process skills are Claude Code skills invoked at specific pipeline phases. They enforce a structured methodology (e.g., `superpowers:brainstorming` for brainstorming, `superpowers:test-driven-development` for TDD). If configured, they are mandatory — the pipeline will always invoke them.

Options: **No** (default), **Yes**

If **Yes**: ask for each phase independently:

| Phase | Question | Example |
|-------|----------|---------|
| `brainstorming` | Skill for brainstorming? | `superpowers:brainstorming` |
| `planning` | Skill for planning? | `superpowers:writing-plans` |
| `tdd` | Skill for TDD? | `superpowers:test-driven-development` |
| `debugging` | Skill for debugging? | `superpowers:systematic-debugging` |

Each phase can be configured independently — leave blank to skip. Only configured phases will be enforced.

If **No**: skip, don't add the `process_skills` key. The pipeline will brainstorm, plan, do TDD, and debug inline without invoking specific skills.

### 10. Worktree isolation

Multiple worktrees can run concurrently, so each needs isolated system dependencies (database, Redis, etc.). Always ask these questions.

> Which files should be symlinked from the main checkout into worktrees?

These are untracked files (config, dependencies) that worktrees need but shouldn't duplicate. Symlinks are created before env vars and setup commands, so setup commands can use them.

Suggest based on project files:
- `.env` present → suggest `.env`
- `node_modules/` present → suggest `node_modules`
- `vendor/bundle/` present → suggest `vendor/bundle`
- Otherwise → ask if there are untracked files or directories needed for running/testing

If none needed, leave empty.

> Which environment variables should be unique per worktree?

Concurrent worktrees sharing stateful dependencies (databases, Redis, search indexes) will corrupt each other. Ask the user which env vars their project uses to namespace these resources — both for test **and** development environments. A shared development database across worktrees causes schema dump conflicts when different branches run migrations.

Each env var can have value `auto` (generates a random 8-char URL-safe base64 string per worktree) or a fixed literal value.

> What commands should run after creating a worktree?

These run with the env vars exported. Ask the user what commands create and prepare their isolated databases and other dependencies. If the project uses `node_modules` and it isn't symlinked, ask if they need `npm install` or equivalent.

> What commands should run before removing a worktree?

These run with the env vars exported. Ask the user what commands clean up the isolated resources (drop databases, flush caches, etc.).

### 11. Language and commit conventions

> What language for commits, PRs, and review comments?

Default: `en`

> Commit convention?

Options: `conventional` (default), `freeform`

> Use a commit writer agent?

Options: agent name (e.g. `my-commit-agent`), or `null` (default — write inline)

If an agent name is provided, the pipeline delegates commit message authoring to that agent. If `null`, commits are written inline.

### 12. PR/MR preferences

> Delete source branch after merge?

Default: `true`

> Rebase before push?

Default: `true`

> Merge behavior?

Options: `manual` (default), `auto`, `ask`

> Merge strategy?

Options: `squash` (default), `merge`, `rebase`

**Note:** If the git host is GitLab, warn that `rebase` is a project-level setting in GitLab and cannot be requested per merge request via API. Recommend `squash` or `merge` for GitLab projects.

### 13. Code review agents

> Which agents run code review?

Default:
```yaml
agents:
  - pr-review-toolkit:code-reviewer
  - pr-review-toolkit:silent-failure-hunter
optional_agents: []
```

Ask if they want to customize the list. If asked about optional agents, suggest `pr-review-toolkit:comment-analyzer` and `pr-review-toolkit:type-design-analyzer` as examples.

### 14. Review instructions

> Do you have a markdown file with project-specific review guidelines?

These are project-specific rules that review agents and critical checks should enforce (e.g., "all API changes require backward compatibility", "controllers must not contain business logic").

Options: **No** (default), **Yes**

If **Yes**: ask for the file path (suggest `.flowyeah/review-guidelines.md`), validate the file exists, add `code_review.instructions: <path>` to the generated YAML.

If **No**: skip, don't add the key.

### 14b. Review comment evaluation

> Use a skill to evaluate review comments during `flowyeah:respond`?

When configured, this skill is invoked for each unresolved review comment during the respond pipeline's triage step. It produces an assessment (agree/disagree/needs-clarification) with a recommended action (implement/reject/discuss), helping the user make faster triage decisions.

Options: **No** (default), **Yes**

If **Yes**: ask for the skill name. Add `code_review.evaluation_skill: <skill>` to the generated YAML.

If **No**: skip, don't add the key. Comments will be presented raw without automated assessment.

### 14c. Impact analysis executor

> Override the built-in Impact Analysis step (`3c` in `flowyeah:review`) with a custom agent?

By default, `flowyeah:review` runs a built-in, read-only tracer for the impact step (caller ripple, contract/interface breaks, feature coupling). Configuring an agent here swaps that executor for one that can do deeper tracing (e.g. LSP/codegraph in a review worktree). The step always runs either way — this only changes who runs it. Review-only; not used by `flowyeah:build`.

Options: **No** (default, built-in tracer), **Yes**

If **Yes**: ask for the agent name. Add `code_review.impact_analysis: <agent>` to the generated YAML.

If **No**: skip, don't add the key.

### 15. Issues

> Create issues automatically when the source wasn't an issue tracker?

Options: `ask` (default), `always`, `never`

**If the user chose `always` or `ask`:**

> Which adapter handles issue creation?

Options: list the adapters selected in step 2 that support issue creation (gitlab, github, linear). Bugsink and New Relic are read-only sources — they cannot create issues.

**If the user chose `linear` as issues adapter:**

> Which Linear team should issues be created in? (leave blank to ask each time)

Query available teams via `mcp__plugin_linear_linear__list_teams()` and present as options. If the user picks a team, set `adapters.linear.team: <team>`. If they leave it blank, omit the key — the pipeline will ask at runtime.

**If the user chose `never`:** skip the adapter question.

### 16. Hooks

> Do you want to configure project-specific hooks for pipeline events?

Hooks are markdown files with instructions that the AI follows at specific pipeline points. They let you plug in project-specific behavior (e.g., milestone association after merge).

**Available hook points:**
- `after_create` — runs after PR/MR creation (e.g., post to Slack, link external trackers)
- `after_merge` — runs after a successful merge, before marking the task done

If the user wants hooks, ask for the file path for each hook point (default: `.flowyeah/hooks/<hook-name>.md`). Remind the user they need to create the file with the instructions.

If the user doesn't want hooks, skip this section entirely (no `hooks` key in YAML).

## Generate

Build `flowyeah.yml` from answers and write to project root:

```yaml
language: <answer>

git:
  default_branch: <answer>

testing:
  command: <answer>
  scope: <answer>

implementation:
  brainstorm: <answer>
  approval: <answer>
  process_skills:                        # omit section entirely if no skills configured
    brainstorming: <answer>
    planning: <answer>
    tdd: <answer>
    debugging: <answer>

commits:
  conventions: <answer>
  writer: <answer>

pull_requests:
  delete_source_branch: <answer>
  rebase: <answer>
  merge: <answer>
  merge_strategy: <answer>

code_review:
  agents:
    - <answer>
  optional_agents:
    - <answer>
  instructions: <answer>                  # omit if not configured
  evaluation_skill: <answer>              # omit if not configured
  impact_analysis: <answer>               # omit if not configured

issues:
  adapter: <answer>
  create_when_missing: <answer>

worktree:
  symlinks:
    - <answer>
  env:
    - <answer>: auto
  setup:
    - <answer>
  teardown:
    - <answer>

hooks:                             # omit section entirely if no hooks
  pr:
    after_create: <answer>         # path to markdown file, e.g. .flowyeah/hooks/after-pr-create.md
    after_merge: <answer>          # path to markdown file, e.g. .flowyeah/hooks/after-merge.md

adapters:
  <adapter>:
    <config keys>

git_host: <answer>
```

Tell the user to review the file. Then proceed with the original command — the pipeline will carry `flowyeah.yml` into the worktree and include it in the first feature-branch commit.

## Reconcile Mode

Entered only from `flowyeah:check` when an existing `flowyeah.yml` is missing
optional adapter keys. This is NOT the full setup — it never runs from the build
pipeline and never re-creates the file.

Input from `check`: one or more adapter names, each with its list of absent
optional keys (from that adapter's `config-schema.md`).

Process:

1. For each absent key, ask the question already defined above for that adapter
   (e.g. the `bugsink` `on_merge` questions, the `linear` `on_start` questions).
   The adapter's `config-schema.md` says *which* keys are missing; the question
   wording lives here.
2. Never ask about keys already set in the file. Only the keys `check` reported
   absent.
3. Write only the answered keys into the existing `flowyeah.yml`, under their
   `adapters.<name>` block, leaving every other line untouched. When a
   question's write template shows sibling sub-keys together (e.g. `bugsink`
   `on_merge.resolve` and `on_merge.comment`), write only the sub-key(s) just
   answered — never re-emit an already-set sibling.
4. If the user declines a given key, leave it absent (its default applies).

Then tell the user what changed and stop — do not proceed to any pipeline.
