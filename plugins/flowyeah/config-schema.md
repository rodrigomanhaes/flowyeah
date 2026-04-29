# flowyeah.yml Configuration Schema

Single source of truth for `flowyeah.yml` configuration. Referenced by setup, build skill, review skill, and config validation.

## Current Schema

| Key | Type | Values | Default | Notes |
|-----|------|--------|---------|-------|
| `language` | string | any | `en` | Used for commits, PRs, and review comments |
| `git.default_branch` | string | any | `main` | Target branch for PRs/MRs and rebase |
| `git_host` | string | adapter key | **required** | Must have `adapters/<git_host>/hosting.md` |
| `testing.command` | string | any | **required** | Shell command to run tests. Suggest based on project files if missing |
| `testing.scope` | string | `related` \| `full` | `related` | `related` = changed files + related specs; `full` = entire suite |
| `implementation.brainstorm` | string | `always` \| `auto` | `auto` | `always` = brainstorm every task; `auto` = AI decides based on complexity |
| `implementation.approval` | string | `always` \| `auto` | `auto` | `always` = present for approval before push; `auto` = AI assesses risk |
| `implementation.process_skills.brainstorming` | string | skill name | none | **Mandatory** when configured — skill invoked for brainstorming phase. If absent, brainstorm inline. Independent of `implementation.brainstorm` (which controls whether the phase runs, not how) |
| `implementation.process_skills.planning` | string | skill name | none | **Mandatory** when configured — skill invoked for planning phase. If absent, plan inline. Independent of `implementation.brainstorm` |
| `implementation.process_skills.tdd` | string | skill name | none | **Mandatory** when configured — skill invoked for TDD phase. If absent, do TDD inline. Applies even when `brainstorm: auto` skips to direct TDD |
| `implementation.process_skills.debugging` | string | skill name | none | **Mandatory** when configured — skill invoked for debugging/investigation. If absent, debug inline |
| `commits.conventions` | string | `conventional` \| `freeform` | `conventional` | Applied to commits or PR title depending on `merge_strategy` |
| `commits.writer` | string | agent name or `null` | `null` | Agent name = delegate commit message authoring to that agent; `null` = write commit messages inline |
| `pull_requests.delete_source_branch` | boolean | `true` \| `false` | `true` | Delete source branch after merge |
| `pull_requests.rebase` | boolean | `true` \| `false` | `true` | Rebase onto target before push |
| `pull_requests.merge` | string | `auto` \| `manual` \| `ask` | `manual` | `auto` = merge via adapter; `manual` = report URL, never merge; `ask` = prompt user |
| `pull_requests.merge_strategy` | string | `squash` \| `merge` \| `rebase` | `squash` | Determines where commit conventions are applied (PR title vs individual commits) |
| `code_review.agents` | list of strings | agent names | **required** (non-empty) | Always launched during CI wait |
| `code_review.optional_agents` | list of strings | agent names | `[]` | AI decides based on what changed |
| `code_review.instructions` | string | file path (relative to project root) | none | Markdown file with project-specific review guidelines. Read once during config validation. Contents injected into review agents and evaluated as additional critical checks. |
| `code_review.evaluation_skill` | string | skill name | none | Skill invoked during `flowyeah:respond` triage to evaluate each review comment. If absent, comments are presented raw without assessment. |
| `issues.create_when_missing` | string | `ask` \| `always` \| `never` | `ask` | Controls issue creation when source is not an issue tracker |
| `issues.adapter` | string | adapter key | conditional | Required when `create_when_missing` is `ask` or `always`. Must support issue creation (gitlab, github, or linear) |
| `worktree.symlinks` | list of strings | relative paths | `[]` | Paths relative to project root. Each is symlinked from the worktree to the main checkout. Created before env/setup. |
| `worktree.env` | list of single-key maps | `auto` = random value | `[]` | Each entry is a single `KEY: value` or `KEY: auto` map (generates random 8-char URL-safe base64). Example: `[{TEST_ENV: auto}, {REDIS_DB: auto}]` |
| `worktree.setup` | list of strings | commands | `[]` | Run after worktree creation with env exported |
| `worktree.teardown` | list of strings | commands | `[]` | Run before worktree removal with env exported |
| `hooks.pr.after_create` | string | file path relative to project root | none | Markdown file with instructions executed after PR/MR creation |
| `hooks.pr.after_merge` | string | file path relative to project root | none | Markdown file with instructions executed after successful merge |
| `adapters.<name>` | map | schema-free | — | Each adapter defines and validates its own keys. Must have `adapters/<name>/connection.md` |

## Validation Rules

| Rule | Severity | Message |
|------|----------|---------|
| `git_host` must be present | error | "git_host is required" |
| `git_host` adapter must have `adapters/<git_host>/hosting.md` | error | "git_host adapter '\<name>' has no hosting.md" |
| Each adapter in `adapters` must have `adapters/<name>/connection.md` | error | "Adapter '\<name>' has no connection.md" |
| `testing.command` must be present | error | "testing.command is required" |
| `code_review.agents` must be non-empty | error | "code_review.agents is required and must not be empty" |
| `code_review.instructions` must be a relative path (if present) | error | "code_review.instructions must be a relative path: '<path>'" |
| `code_review.instructions` file must exist (if present) | error | "code_review.instructions file not found: '<path>'" |
| `issues.adapter` required when `create_when_missing` is `ask` or `always` | error | "issues.adapter is required when create_when_missing is '\<value>'" |
| `issues.adapter` must support issue creation (gitlab, github, or linear) | error | "issues.adapter '\<name>' does not support issue creation (only gitlab, github, linear)" |
| `issues.adapter` must be a key in `adapters` | error | "issues.adapter '\<name>' is not configured in adapters" |
| `hooks.pr.after_create` must be a relative path (if present) | error | "hooks.pr.after_create must be a relative path: '<path>'" |
| `hooks.pr.after_create` file must exist (if present) | error | "hooks.pr.after_create file not found: '<path>'" |
| `hooks.pr.after_merge` must be a relative path (if present) | error | "hooks.pr.after_merge must be a relative path: '<path>'" |
| `hooks.pr.after_merge` file must exist (if present) | error | "hooks.pr.after_merge file not found: '<path>'" |
| `worktree.symlinks` entries must be relative paths | error | `worktree.symlinks entries must be relative paths: '<path>'` |
| `worktree.symlinks` entries must not escape project root (`../`) | error | `worktree.symlinks entry escapes project root: '<path>'` |
| `worktree.env` entries must be single-key maps (e.g., `{KEY: auto}`) | error | "worktree.env entry must be a single-key map, got: '\<value>'" |
| `worktree.env` map values must be strings | error | "worktree.env value for '\<key>' must be a string" |
| `worktree.setup` entries must be strings | error | "worktree.setup entry must be a string, got: '\<value>'" |
| `worktree.teardown` entries must be strings | error | "worktree.teardown entry must be a string, got: '\<value>'" |
| `git_host: gitlab` + `merge_strategy: rebase` | warning | "GitLab rebase is a project-level setting, not controllable per MR via API. Recommend squash or merge." |

## Deprecated Keys

| Key | Removed in | Migration |
|-----|-----------|-----------|
| `sources` | 2026-03-02 | Remove from config. Adapters with `source.md` are automatic sources. |
| `hosting` | 2026-03-03 | Rename to `git_host`. |
| `hooks.after_merge` | 2026-03-06 | Move to `hooks.pr.after_merge`. |
