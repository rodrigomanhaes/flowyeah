# flowyeah.yml Interactive Setup

Shared setup instructions used by both `flowyeah:build` and `flowyeah:review` when `flowyeah.yml` is missing.

## When to Run

If `flowyeah.yml` does not exist in the project root, run this interactive setup before proceeding.

## Schema Reference

Valid keys, types, defaults, and allowed values are defined in `config-schema.md` at the plugin root. This setup asks questions to populate those keys.

## Questions

Ask each question in order. Use sensible defaults based on the project context.

### 1. Hosting platform

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

Default: include the hosting platform. When `github` is selected as hosting or as an adapter, suggest also enabling `ghactions`.

Any adapter with a `source.md` file is automatically available as a source — no separate list needed.

### 3. Adapter config

For each selected adapter, ask for required config:

| Adapter | Questions |
|---------|-----------|
| `gitlab` | URL, token env var name, token source file, project ID |
| `github` | (none — uses `gh` CLI) |
| `linear` | (none — uses MCP) |
| `bugsink` | URL, token env var name, token source file |
| `newrelic` | Token env var name, token source file, account ID |
| `ghactions` | (none — uses `gh` CLI, same as GitHub) |

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

### 6b. Brainstorming

> Always brainstorm before implementing, or let AI decide?

Options: `always`, `auto` (default)

- **`always`** — every task goes through brainstorm → plan → TDD. Recommended for legacy, large, or critical codebases where even small changes need discussion.
- **`auto`** — AI assesses complexity: trivial tasks skip brainstorming, non-trivial tasks get the full cycle. Recommended for greenfield projects.

### 6c. Implementation approval

> Approve implementation before pushing, or let AI decide?

Options: `always`, `auto` (default)

- **`always`** — present the implementation for developer approval before pushing. Recommended for legacy, large, or critical codebases where every change needs human review before leaving the local environment.
- **`auto`** — AI assesses risk: straightforward changes push automatically, complex or high-risk changes ask. Recommended for greenfield projects.

### 6d. Worktree isolation

Multiple worktrees can run concurrently, so each needs isolated system dependencies (database, Redis, etc.). Always ask these questions.

> Which environment variables should be unique per worktree?

Suggest based on project files:
- `Gemfile` present → suggest `TEST_ENV_NUMBER` (Rails convention — `database.yml` appends this to the database name for parallel test databases)
- Any project → ask if they use Redis, Elasticsearch, or other stateful services that need isolation, and suggest corresponding env vars

Each env var can have value `auto` (generates a random 8-char URL-safe base64 string per worktree) or a fixed literal value.

> What commands should run after creating a worktree?

These run with the env vars exported. Suggest based on project files:
- `Gemfile` present → suggest `bundle exec rails db:test:prepare`
- `package.json` present → suggest `npm install` (if `node_modules` isn't shared)
- Otherwise → ask

> What commands should run before removing a worktree?

These run with the env vars exported. Suggest based on project files:
- `Gemfile` present → suggest `bundle exec rails db:drop DISABLE_DATABASE_ENVIRONMENT_CHECK=1`
- Otherwise → ask

### 7. Language and commit conventions

> What language for commits, PRs, and review comments?

Default: `en`

> Commit convention?

Options: `conventional` (default), `freeform`

> Use a commit writer agent?

Options: `git-commit-writer` (default), `null` (write manually)

If `git-commit-writer`, the pipeline delegates commit message authoring to that agent. If `null`, commits are written inline.

### 8. PR/MR preferences

> Delete source branch after merge?

Default: `true`

> Rebase before push?

Default: `true`

> Merge behavior?

Options: `manual` (default), `auto`, `ask`

> Merge strategy?

Options: `squash` (default), `merge`, `rebase`

**Note:** If the hosting platform is GitLab, warn that `rebase` is a project-level setting in GitLab and cannot be requested per merge request via API. Recommend `squash` or `merge` for GitLab projects.

### 9. Code review agents

> Which agents run code review?

Default:
```yaml
agents:
  - pr-review-toolkit:code-reviewer
  - pr-review-toolkit:silent-failure-hunter
optional_agents:
  - pr-review-toolkit:comment-analyzer
  - pr-review-toolkit:type-design-analyzer
```

Ask if they want to customize the list.

### 10. Issues

> Create issues automatically when the source wasn't an issue tracker?

Options: `ask` (default), `always`, `never`

**If the user chose `always` or `ask`:**

> Which adapter handles issue creation?

Options: list the adapters selected in step 2 that support issue creation (gitlab, github, linear). Bugsink and New Relic are read-only sources — they cannot create issues.

**If the user chose `never`:** skip the adapter question.

### 11. Hooks

> Do you want to configure project-specific hooks for pipeline events?

Hooks are markdown files with instructions that the AI follows at specific pipeline points. They let you plug in project-specific behavior (e.g., milestone association after merge).

**Available hook points:**
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

issues:
  adapter: <answer>
  create_when_missing: <answer>

worktree:
  env:
    - <answer>: auto
  setup:
    - <answer>
  teardown:
    - <answer>

hooks:                             # omit section entirely if no hooks
  after_merge: <answer>            # path to markdown file, e.g. .flowyeah/hooks/after-merge.md

adapters:
  <adapter>:
    <config keys>

hosting: <answer>
```

Tell the user to review and commit the file. Then proceed with the original command.
