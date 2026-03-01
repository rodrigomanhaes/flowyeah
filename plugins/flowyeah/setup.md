# flowyeah.yml Interactive Setup

Shared setup instructions used by both `flowyeah:build` and `flowyeah:review` when `flowyeah.yml` is missing.

## When to Run

If `flowyeah.yml` does not exist in the project root, run this interactive setup before proceeding.

## Questions

Ask each question in order. Use sensible defaults based on the project context.

### 1. Hosting platform

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

Default: include the hosting platform.

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

> Which adapter handles issue tracking?

Options: list the adapters selected in step 2 that have a `source.md` (gitlab, github, linear).

This is required when `create_when_missing` is `always` or `ask`. If the user chose `never`, skip this question.

> Create issues automatically when the source wasn't an issue tracker?

Options: `ask` (default), `always`, `never`

## Generate

Build `flowyeah.yml` from answers and write to project root:

```yaml
version: 1

language: <answer>

git:
  default_branch: <answer>

testing:
  command: <answer>
  scope: <answer>

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

adapters:
  <adapter>:
    <config keys>

sources:
  - <adapter>

hosting: <answer>
```

Tell the user to review and commit the file. Then proceed with the original command.
