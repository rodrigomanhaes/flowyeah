# flowyeah.yml Configuration Schema

Single source of truth for `flowyeah.yml` configuration. Referenced by setup, build skill, review skill, and config validation.

## Current Schema

| Key | Type | Values | Default | Notes |
|-----|------|--------|---------|-------|
| `language` | string | any | `en` | Used for commits, PRs, and review comments |
| `git.default_branch` | string | any | `main` | Target branch for PRs/MRs and rebase |
| `hosting` | string | adapter key | **required** | Must have `adapters/<hosting>/hosting.md` |
| `testing.command` | string | any | **required** | Shell command to run tests. Suggest based on project files if missing |
| `testing.scope` | string | `related` \| `full` | `related` | `related` = changed files + related specs; `full` = entire suite |
| `implementation.brainstorm` | string | `always` \| `auto` | `auto` | `always` = brainstorm every task; `auto` = AI decides based on complexity |
| `implementation.approval` | string | `always` \| `auto` | `auto` | `always` = present for approval before push; `auto` = AI assesses risk |
| `commits.conventions` | string | `conventional` \| `freeform` | `conventional` | Applied to commits or PR title depending on `merge_strategy` |
| `commits.writer` | string | agent name or `null` | `git-commit-writer` | `null` = write commit messages inline |
| `pull_requests.delete_source_branch` | boolean | `true` \| `false` | `true` | Delete source branch after merge |
| `pull_requests.rebase` | boolean | `true` \| `false` | `true` | Rebase onto target before push |
| `pull_requests.merge` | string | `auto` \| `manual` \| `ask` | `manual` | `auto` = merge via adapter; `manual` = report URL, never merge; `ask` = prompt user |
| `pull_requests.merge_strategy` | string | `squash` \| `merge` \| `rebase` | `squash` | Determines where commit conventions are applied (PR title vs individual commits) |
| `code_review.agents` | list of strings | agent names | **required** (non-empty) | Always launched during CI wait |
| `code_review.optional_agents` | list of strings | agent names | `[]` | AI decides based on what changed |
| `issues.create_when_missing` | string | `ask` \| `always` \| `never` | `ask` | Controls issue creation when source is not an issue tracker |
| `issues.adapter` | string | adapter key | conditional | Required when `create_when_missing` is `ask` or `always`. Must support issue creation (gitlab, github, or linear) |
| `worktree.symlinks` | list of strings | relative paths | `[]` | Paths relative to project root. Each is symlinked from the worktree to the main checkout. Created before env/setup. |
| `worktree.env` | list of key-value maps | `auto` = random value | `[]` | Each entry is `KEY: value` or `KEY: auto` (generates random 8-char URL-safe base64) |
| `worktree.setup` | list of strings | commands | `[]` | Run after worktree creation with env exported |
| `worktree.teardown` | list of strings | commands | `[]` | Run before worktree removal with env exported |
| `hooks.after_merge` | string | file path relative to project root | none | Markdown file with instructions executed after successful merge |
| `adapters.<name>` | map | schema-free | — | Each adapter defines and validates its own keys. Must have `adapters/<name>/connection.md` |

## Validation Rules

| Rule | Severity | Message |
|------|----------|---------|
| `hosting` must be present | error | "hosting is required" |
| `hosting` adapter must have `adapters/<hosting>/hosting.md` | error | "Hosting adapter '\<name>' has no hosting.md" |
| Each adapter in `adapters` must have `adapters/<name>/connection.md` | error | "Adapter '\<name>' has no connection.md" |
| `testing.command` must be present | error | "testing.command is required" |
| `code_review.agents` must be non-empty | error | "code_review.agents is required and must not be empty" |
| `issues.adapter` required when `create_when_missing` is `ask` or `always` | error | "issues.adapter is required when create_when_missing is '\<value>'" |
| `issues.adapter` must support issue creation (gitlab, github, or linear) | error | "issues.adapter '\<name>' does not support issue creation (only gitlab, github, linear)" |
| `worktree.symlinks` entries must be relative paths | error | `worktree.symlinks entries must be relative paths: '<path>'` |
| `worktree.symlinks` entries must not escape project root (`../`) | error | `worktree.symlinks entry escapes project root: '<path>'` |
| `hosting: gitlab` + `merge_strategy: rebase` | warning | "GitLab rebase is a project-level setting, not controllable per MR via API. Recommend squash or merge." |

## Deprecated Keys

| Key | Removed in | Migration |
|-----|-----------|-----------|
| `sources` | 2026-03-02 | Remove from config. Adapters with `source.md` are automatic sources. |
