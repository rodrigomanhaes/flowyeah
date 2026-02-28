# flowyeah.yml Interactive Setup

Shared setup instructions used by both `flowyeah:build` and `flowyeah:review` when `flowyeah.yml` is missing.

## When to Run

If `flowyeah.yml` does not exist in the project root, run this interactive setup before proceeding.

## Questions

Ask each question in order. Use sensible defaults based on the project context.

### 1. Sink platform

> Where do you create PRs/MRs?

Detect from `git remote get-url origin`:
- Contains `github.com` → suggest `github`
- Contains `gitlab` → suggest `gitlab`
- Otherwise → ask

### 2. Source adapters

> Which integrations do you use for issues/errors?

Options (multi-select):
- **gitlab** — GitLab issues
- **github** — GitHub issues
- **linear** — Linear issues (requires MCP plugin)
- **bugsink** — Bugsink errors (requires API token)
- **newrelic** — New Relic errors (requires API key)

Default: include the sink platform.

### 3. Adapter config

For each selected adapter, ask for required config:

| Adapter | Questions |
|---------|-----------|
| `gitlab` | URL, token env var name, token source file, project ID |
| `github` | (none — uses `gh` CLI) |
| `linear` | (none — uses MCP) |
| `bugsink` | URL, token env var name, token source file |
| `newrelic` | Token env var name, token source file, account ID |

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

### 7. Commit conventions

> Commit message language?

Default: `en`

> Commit convention?

Options: `conventional` (default), `freeform`

### 8. PR/MR preferences

> Delete source branch after merge?

Default: `true`

> Rebase before push?

Default: `true`

> Merge behavior?

Options: `manual` (default), `auto`, `ask`

> Merge strategy?

Options: `squash` (default), `merge`, `rebase`

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

## Generate

Build `flowyeah.yml` from answers and write to project root:

```yaml
git:
  default_branch: <answer>

testing:
  command: <answer>
  scope: <answer>

commits:
  language: <answer>
  conventions: <answer>

pull_requests:
  delete_source_branch: <answer>
  rebase: <answer>
  merge: <answer>
  merge_strategy: <answer>
  language: <answer>

code_review:
  agents:
    - <answer>
  optional_agents:
    - <answer>

adapters:
  <adapter>:
    <config keys>

sources:
  - <adapter>

sink: <answer>
```

Tell the user to review and commit the file. Then proceed with the original command.
