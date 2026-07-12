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
| `code_review.instructions` | string | file path (relative to project root) | none | Project-specific guidelines (the *what* a project cares about). Read once during config validation. Consumed by `flowyeah:review`, `flowyeah:respond`, and `flowyeah:build`: in review, injected into review agents and evaluated as an inline critical check; in respond, used to evaluate each comment during triage; in build, injected into the review agents launched during the CI wait (step 7b). Guidelines may reference external resources (e.g. a Linear issue, a docs URL) that the skill resolves via available tools. |
| `code_review.evaluation_skill` | string | skill name | none | General feedback-evaluation methodology (the *how*, e.g. `superpowers:receiving-code-review`). Skill invoked during `flowyeah:respond` triage to evaluate each review comment. Orthogonal to `code_review.instructions`: the skill supplies method, instructions supply project specifics. If neither is configured, comments are presented raw without assessment. |
| `code_review.impact_analysis` | string | agent name | none | Overrides the built-in deterministic Impact Analysis step (`3c` in `flowyeah:review`) with the named agent. Absent = built-in deterministic tracing runs. The step always runs; only its executor is swappable — it cannot be disabled. Review-only; not consumed by `flowyeah:build`. |
| `issues.create_when_missing` | string | `ask` \| `always` \| `never` | `ask` | Controls issue creation when source is not an issue tracker |
| `issues.adapter` | string | adapter key | conditional | Required when `create_when_missing` is `ask` or `always`. Must support issue creation (gitlab, github, or linear) |
| `worktree.symlinks` | list of strings | relative paths | `[]` | Paths relative to project root. Each is symlinked from the worktree to the main checkout. Created before env/setup. |
| `worktree.env` | list of single-key maps | `auto` = random value | `[]` | Each entry is a single `KEY: value` or `KEY: auto` map (generates random 8-char URL-safe base64). Example: `[{TEST_ENV: auto}, {REDIS_DB: auto}]` |
| `worktree.setup` | list of strings | commands | `[]` | Run after worktree creation with env exported |
| `worktree.teardown` | list of strings | commands | `[]` | Run before worktree removal with env exported |
| `hooks.pr.after_create` | string | file path relative to project root | none | Markdown file with instructions executed after PR/MR creation |
| `hooks.pr.after_merge` | string | file path relative to project root | none | Markdown file with instructions executed after successful merge |
| `adapters.<name>` | map | keys declared in `adapters/<name>/config-schema.md` | — | Must have `adapters/<name>/connection.md`. If `adapters/<name>/config-schema.md` exists, its keys are validated (required present, enums valid, unknown flagged) |

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
| `code_review.impact_analysis` must be a non-empty string (if present) | error | "code_review.impact_analysis must be a non-empty agent name" |
| `issues.adapter` required when `create_when_missing` is `ask` or `always` | error | "issues.adapter is required when create_when_missing is '\<value>'" |
| `issues.adapter` must support issue creation (gitlab, github, or linear) | error | "issues.adapter '\<name>' does not support issue creation (only gitlab, github, linear)" |
| `issues.adapter` must be a key in `adapters` | error | "issues.adapter '\<name>' is not configured in adapters" |
| `git_host` must be a key in `adapters` | error | "git_host '\<name>' is not configured in adapters — add an adapters.\<name> block with its required keys" |
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
| Required adapter key (per `adapters/<name>/config-schema.md`) present | error | "adapters.\<name>.\<key> is required" |
| Enum-valued adapter key within its allowed set | error | "adapters.\<name>.\<key> must be one of \<values>: '\<value>'" |
| Adapter key present but not declared in its config-schema.md | warning | "adapters.\<name>.\<key> is not a known key for adapter '\<name>'" |
| `git_host: gitlab` + `merge_strategy: rebase` | warning | "GitLab rebase is a project-level setting, not controllable per MR via API. Recommend squash or merge." |

## Deprecated Keys

| Key | Removed in | Migration |
|-----|-----------|-----------|
| `sources` | 2026-03-02 | Remove from config. Adapters with `source.md` are automatic sources. |
| `hosting` | 2026-03-03 | Rename to `git_host`. |
| `hooks.after_merge` | 2026-03-06 | Move to `hooks.pr.after_merge`. |
