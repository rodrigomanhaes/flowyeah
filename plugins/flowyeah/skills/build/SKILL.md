---
name: build
description: Use when starting work from any source - ideas, issues, conversation context, or plan files - that needs implementation with git isolation, TDD, code review, and CI verification
---

# flowyeah:build — Plan-to-PR Pipeline

Single command. Takes any source, produces tested, reviewed, merged PRs.

```
flowyeah:build [from <source>] [--continuous]
```

## Sources

| Source | Example | Adapter |
|--------|---------|---------|
| No argument | `flowyeah:build` | Resume from `tmp/flowyeah/plans/` or ask |
| Conversation | `flowyeah:build` (mid-conversation) | Use current context |
| File | `flowyeah:build from docs/plans/redesign.md` | Read file directly |
| Prefix-based | `flowyeah:build from PREFIX:ID` | Load `adapters/<prefix>/source.md` |

**Prefix-based sources** match the command prefix to a source adapter and config in `flowyeah.yml`:

- `flowyeah:build from GITLAB:#5588` → reads `adapters.gitlab` config → loads `adapters/gitlab/source.md` (+ `connection.md`)
- `flowyeah:build from GITHUB:#45` → reads `adapters.github` config → loads `adapters/github/source.md` (+ `connection.md`)
- `flowyeah:build from LINEAR:PROJ-123` → reads `adapters.linear` config → loads `adapters/linear/source.md` (+ `connection.md`)
- `flowyeah:build from BUGSINK:45678` → reads `adapters.bugsink` config → loads `adapters/bugsink/source.md` (+ `connection.md`)
- `flowyeah:build from NEWRELIC:MXxBUE18...` → reads `adapters.newrelic` config → loads `adapters/newrelic/source.md` (+ `connection.md`)

New source? Create an adapter directory with `connection.md` + `source.md`, add config to `flowyeah.yml` under `adapters`. Zero changes to this skill.

If source is prose without tasks: brainstorm with the user, generate a task plan, save as canonical format.

## Canonical Plan Format

```markdown
# Plan: <title>

## Tasks
- [ ] Task description
- [ ] Another task
- [x] Completed task
```

Saved to `tmp/flowyeah/plans/<key>.md` in the main checkout.

**Plan key derivation:**

| Source | Key | Example path |
|--------|-----|--------------|
| `GITLAB:#5588` | `gitlab-5588` | `tmp/flowyeah/plans/gitlab-5588.md` |
| `LINEAR:PROJ-123` | `linear-proj-123` | `tmp/flowyeah/plans/linear-proj-123.md` |
| `GITHUB:#45` | `github-45` | `tmp/flowyeah/plans/github-45.md` |
| `BUGSINK:45678` | `bugsink-45678` | `tmp/flowyeah/plans/bugsink-45678.md` |
| `NEWRELIC:MXxBUE18...` | `newrelic-mxxbue` | `tmp/flowyeah/plans/newrelic-mxxbue.md` |
| File source | slugified filename | `tmp/flowyeah/plans/redesign.md` |
| Conversation (no source) | slugified work description | `tmp/flowyeah/plans/webhook-retry.md` |

The `tmp/` directory should be gitignored. Plans are developer process artifacts, not versioned deliverables.

## Pipeline

```dot
digraph pipeline {
    rankdir=TB;
    node [shape=box];

    validate [label="0. Validate Config\n(keys, adapters, auth)"];
    resolve [label="1. Resolve Source\n(read-only, main checkout)"];
    pick [label="2. Pick Task(s)"];
    worktree [label="3. Worktree + Branch"];
    verify_wt [label="3b. Verify Isolation" shape=diamond];
    implement [label="4. Brainstorm → Plan → TDD"];
    commit [label="5. Commit"];
    deliver [label="6. Test → Rebase → Push"];
    pr [label="7. Create PR/MR"];
    ci_loop [label="7b. CI + Code Review Loop" shape=diamond];
    mark [label="8. Mark Task Done"];
    cleanup [label="9. Cleanup Worktree"];
    next [label="Next task?" shape=diamond];

    validate -> resolve -> pick -> worktree -> verify_wt;
    verify_wt -> implement [label="in worktree"];
    verify_wt -> worktree [label="NOT in worktree\nSTOP"];
    implement -> commit -> deliver -> pr -> ci_loop;
    ci_loop -> commit [label="issues found\nfix → commit → push\nskip review on retry"];
    ci_loop -> mark [label="CI green +\nreview clean"];
    mark -> cleanup -> next;
    next -> pick [label="--continuous"];
    next -> resolve [label="done"];
}
```

### 0. Validate Configuration

Before any pipeline step, validate the loaded `flowyeah.yml`:

1. **Required keys:** `hosting` must be present and point to an adapter with `hosting.md`. `code_review.agents` must be non-empty.
2. **Adapter references:** every entry in `sources` must have a corresponding `adapters/<name>/source.md`. The `hosting` value must have `adapters/<hosting>/hosting.md`. If `issues.adapter` is set, it must have `adapters/<adapter>/source.md`.
3. **Auth verification:** for each adapter that will be used in this run (determined by the source command and hosting), verify credentials are reachable:
   - Adapters with `token_env` + `token_source` → check the env var exists (via the token source file)
   - `github` → verify `gh auth status` succeeds
   - `linear` → verify Linear MCP is available
4. **Report all issues at once** — don't fail on the first error. Collect all validation failures and present them together so the user can fix everything in one pass.

If validation fails, STOP with actionable error messages. Do not proceed with a broken config.

### 1. Resolve Source

Parse command arguments, read content, convert to canonical plan format. Save to `tmp/flowyeah/plans/<key>.md`.

- **Prefix source (e.g., `GITLAB:#5588`):** verify prefix is listed in `flowyeah.yml` `sources`. Load `adapters/<prefix>/connection.md` + `adapters/<prefix>/source.md`, read its config from `flowyeah.yml` `adapters.<prefix>`, follow the adapter's instructions to fetch and convert to canonical format. Key: `<prefix>-<id>` (e.g., `gitlab-5588`).
- **File source:** read file, convert to canonical format. Key: slugified filename without extension. The source file is never mutated — the plan is a copy in `tmp/`.
- **Prose/idea:** brainstorm with user, generate tasks. Key: slugified description of the work (ask or infer from conversation).
- **No source + plans exist in `tmp/flowyeah/plans/`:**
  - One plan with unchecked tasks → resume it.
  - Multiple plans with unchecked tasks → show list, ask which to resume.
- **No source + no plans:** ask what the user wants to work on.

### 2. Pick Task(s)

- Find first unchecked `[ ]` task in the active plan (`tmp/flowyeah/plans/<key>.md`, from main checkout)
- Check claims: `git branch -a` — branch with task slug exists → skip to next
- Nested tasks: pick first unchecked leaf
- **No tasks remaining:** Report "Plan complete" and exit
- **Small related tasks:** batch into one worktree/branch/PR. Use judgment unless told otherwise.

### 3. Worktree + Branch

Create worktree and branch. **Always worktree, always branch.**

**Before creating the worktree**, verify `flowyeah.yml` is committed. If it's untracked or modified, commit it first — worktrees are created from the current branch HEAD, so uncommitted files won't be present in the worktree and the injection hook will silently fail.

```bash
# Read git.default_branch from flowyeah.yml (default: main)
git checkout $DEFAULT_BRANCH && git pull origin $DEFAULT_BRANCH
mkdir -p .flowyeah/worktrees tmp/flowyeah/plans
git check-ignore -q .flowyeah 2>/dev/null || echo ".flowyeah/" >> .gitignore
git check-ignore -q tmp 2>/dev/null || echo "tmp/" >> .gitignore
git worktree add .flowyeah/worktrees/<type>-<slug> -b <type>/<slug>
```

**Branch naming:**

| Source | Branch name |
|--------|-------------|
| LINEAR:PROJ-123 | `<type>/PROJ-123` |
| GITLAB:#5588 | `<type>/5588` |
| GITHUB:#45 | `<type>/45` |
| Prose/idea | `<type>/<slug>` |

**Type inference:**

| Task pattern | Type |
|--------------|------|
| "Add...", "Implement...", "Create..." | `feat` |
| "Fix...", "Resolve...", "Correct..." | `fix` |
| "Refactor...", "Extract...", "Move..." | `refactor` |
| "Update deps", "Configure..." | `chore` |
| Ambiguous | Ask the user |

Create session directory and state files in the worktree:

```bash
mkdir -p .flowyeah
```

Write 4 session files (see Session Management section below).

### 3b. Verify Worktree Isolation

```bash
git rev-parse --show-toplevel | grep -qF '.flowyeah/worktrees/' || echo "NOT IN WORKTREE — STOP"
```

**NEVER write code outside a worktree.** Analysis and planning are OK. Code changes are not.

**Resolving the main checkout path** (needed for plan files in `tmp/` and cleanup):

```bash
MAIN_WORKTREE=$(git worktree list --porcelain | head -1 | sed 's/worktree //')
```

Use `$MAIN_WORKTREE/tmp/flowyeah/plans/<key>.md` to access plan files from inside a worktree.

### 4. Implement

**Trivial tasks** (single config change, rename, docs-only): TDD directly.

**Non-trivial tasks:**
1. **Brainstorm** — explore task, constraints, edge cases. Use `superpowers:brainstorming`.
2. **Plan** — create implementation steps. Use `superpowers:writing-plans`.
3. **TDD** — test first, minimal code, refactor. Use `superpowers:test-driven-development`.
4. Update `state.md` on every phase transition.

### 5. Commit

Commit using project conventions from `flowyeah.yml`:
- Language: `language`
- Conventions: `commits.conventions`
- Writer agent: `commits.writer` (if set, delegate to that agent; otherwise commit manually)

### 6. Test → Rebase → Push

```bash
# Test (from flowyeah.yml testing.command)
<testing.command> <scoped-spec-files>

# Rebase (if pull_requests.rebase is true)
git fetch origin $DEFAULT_BRANCH && git rebase origin/$DEFAULT_BRANCH

# Push (force-with-lease only after rebase; regular push otherwise)
if pull_requests.rebase; then
  git push -u origin $BRANCH --force-with-lease
else
  git push -u origin $BRANCH
fi
```

**Test scope** (`testing.scope`):
- `related` — directly changed files and related integration/feature/system/e2e specs
- `full` — run the full test suite

### 7. Create PR/MR

Load the hosting adapter from `adapters/<hosting>/connection.md` + `adapters/<hosting>/hosting.md`, read its config from `flowyeah.yml` `adapters.<hosting>`, and follow the adapter's instructions to create the PR/MR.

**The skill provides these values to the adapter:**
- **Source branch:** current branch
- **Target branch:** `git.default_branch`
- **Title:** descriptive, in `language`. Include issue reference if from issue source.
- **Body:** summary of changes. Include `Closes #<issue>` when from an issue source (default close keyword).
- **Delete source branch:** `pull_requests.delete_source_branch`

**After CI + review pass:**
- `pull_requests.merge: auto` → use the hosting adapter to merge
- `pull_requests.merge: manual` → report PR URL and stop
- `pull_requests.merge: ask` → ask the user

Code review results are reported in the terminal only — this is your current work session, not a team review artifact.

### 7b. CI + Code Review Loop

**Do NOT give the prompt back.** Stay in the loop until CI passes and reviews are clean. Use the hosting adapter for CI polling.

**While waiting for CI:**

1. **Run code review agents** from `flowyeah.yml`:
   - **`code_review.agents`** — always launch all of these.
   - **`code_review.optional_agents`** — launch based on what changed (e.g., security-analyst if auth code was touched, code-quality-analyst for large refactors). Use judgment.
   - **If `code_review.agents` is empty or missing: STOP and complain. Do NOT continue without code review.**

2. **Issue creation opportunity.** If the source was NOT an issue tracker, check `issues.create_when_missing`:
   - `ask` — ask the user if an issue should be created
   - `always` — create one automatically via `issues.adapter`
   - `never` — skip

**When results come back:**

- **CI passes AND review clean** → proceed to step 8
- **CI fails** → investigate, fix, restart from step 5 (commit → test → push). Skip code review on retry. Any CI failure is YOUR failure. Assume CI is evergreen.
- **Review agents find issues** → fix, restart from step 5 (commit → test → push). Skip code review on retry — the review already told you what to fix.
- **CI fails 3 times** → STOP and ask for guidance

### 8. Mark Task Done + Close Session

- Promote qualified findings from `.flowyeah/findings.md` to auto memory
- Check `[x]` in `tmp/flowyeah/plans/<key>.md` (from main checkout, after merge)
- If the source was an issue tracker, update the issue status:
  - **GitLab:** auto-closed via `Closes #<iid>` in MR description (no action needed)
  - **GitHub:** auto-closed via `Closes #<number>` in PR body (no action needed)
  - **Linear:** call `save_issue(id: "<id>", state: "Done")` via MCP
  - **Bugsink/New Relic:** no action — errors auto-resolve when the fix is deployed

### 9. Cleanup Worktree

Removes the worktree and everything in it, including `.flowyeah/` session files.

```bash
cd "$MAIN_WORKTREE"
git checkout $DEFAULT_BRANCH && git pull origin $DEFAULT_BRANCH
git worktree remove <worktree-path>
```

## Continuous Mode (`--continuous`)

```
loop:
  1. Pick next task
  2. None left? → "Plan complete" → exit
  3. Worktree → implement → commit → test → push → PR → CI loop
  4. Stop condition? → stop and ask
  5. Success? → back to step 1
```

## Plan Lifecycle

Plans in `tmp/flowyeah/plans/` accumulate over time. Cleanup rules:

- **Completed plans** (all tasks `[x]`): keep for 7 days after last modification, then delete on next `flowyeah:build` invocation
- **Active plans** (unchecked tasks remain): never auto-delete
- **Orphaned plans** (no matching branches, no recent modification >30 days): warn the user and offer to delete

On each `flowyeah:build` run, before resolving the source, check for stale completed plans and clean up silently. Log deletions to stdout so the user knows what was removed.

## Session Management

Session state lives in `.flowyeah/` inside the worktree. It survives context compaction (via hook injection) and crashes (files persist on disk). Cleaned up with the worktree in step 9.

### Session Files

```
.flowyeah/worktrees/<type>-<slug>/
└── .flowyeah/
    ├── state.md       # WHERE — current position + decision context
    ├── mission.md     # WHY — goal, scope, success criteria
    ├── progress.md    # WHAT — task checklist with stats
    └── findings.md    # LEARNED — discoveries, gotchas, insights
```

### state.md — Rich Context (update very frequently)

Must have parseable header lines for crash recovery summaries:

```markdown
# Current State

Type: build
Status: Implementing
Step: 4 (Implement) — TDD phase
Mode: single                          # single | continuous
Task: Webhook retry logic
Source: GITLAB:#5588
Plan: tmp/flowyeah/plans/gitlab-5588.md  # relative to main checkout
Branch: feat/5588
Worktree: .flowyeah/worktrees/feat-5588

## Key Decisions Made
- Chose exponential backoff over linear retry (better for rate-limited APIs)
- Max 5 retries with jitter to avoid thundering herd
- Using ActiveJob retry mechanism rather than custom loop

## What's Been Done
- Brainstormed 3 approaches
- Plan: 4 implementation steps
- Steps 1-2 complete: model and service layer
- Step 3 in progress: controller integration

## Dead Ends
- Tried custom retry loop with sleep — race condition with Sidekiq's own retry
- Tried rescue_from in controller — too late, webhook already marked as failed

## Current Focus
Writing failing feature spec for webhook retry behavior.

## Next Action
Complete the feature spec, then implement the controller action.
```

**Update when:** every pipeline step transition, every phase transition within step 4, after completing subtasks, after discovering dead ends, after making key decisions. The more context here, the better a resumed session performs.

### mission.md — Goal (update rarely)

```markdown
# Mission

Implement webhook retry with exponential backoff for failed deliveries.

## Scope
- Retry mechanism with configurable max attempts
- Exponential backoff with jitter
- Dead letter queue for permanently failed webhooks
- Admin UI to view retry status

## Success Criteria
- [ ] Failing webhooks are retried up to 5 times
- [ ] Backoff is exponential with jitter
- [ ] Permanently failed webhooks go to dead letter queue
- [ ] Admin can see retry history
- [ ] All tests pass, CI green
```

### progress.md — Checklist (update after each item)

```markdown
# Progress

## Items
- [x] Design retry strategy
- [x] Implement retry model
- [ ] Implement retry service
- [ ] Controller integration
- [ ] Feature specs

## Stats
- Total: 5
- Done: 2
- Remaining: 3
```

### findings.md — Accumulated Knowledge (update after discoveries)

```markdown
# Findings

## Summary
ActiveJob's retry_on has a quirk: exponential backoff is capped at
the job's max wait time, not the retry count. Set both explicitly.

## Details

### ActiveJob retry_on gotcha
The `wait` parameter in retry_on accepts a lambda but the exponential
calculation is capped by `retry_jitter` config. Must set both:
  retry_on WebhookError, wait: :polynomially_longer, attempts: 5
  self.retry_jitter = 0.15
```

Keep `## Summary` current — the injection hook only shows the summary section, not full details.

### Hook-Based Injection

Two hooks (installed via this plugin's `hooks/hooks.json`) power session recovery:

1. **`UserPromptSubmit`** — `session-inject.sh` injects all 4 files on every prompt (findings: summary only). This is how state survives context compaction.

2. **`PostToolUse` on Edit/Write** — `session-remind.sh` nudges to update state.md after making changes.

Both scripts are guarded: exit silently if no `flowyeah.yml` in project or no active `.flowyeah/` session.

### Context Compaction Recovery

After compaction, the hook re-injects state automatically:
1. Read injected state to find current position
2. Continue from where `state.md` indicates
3. Do NOT restart the task from scratch

### Crash Recovery

After a crash, the user returns to the main checkout. Run `flowyeah:build`:
1. Scan `.flowyeah/worktrees/*/.flowyeah/state.md` for active sessions
2. If one session: resume it directly
3. If multiple sessions: show summary and ask which to resume
   ```
   Active sessions:
   1. feat-5588         → Webhook retry logic (Step 4: TDD)
   2. fix-5590          → Payment validation (Step 7b: CI wait)
   3. chore-update-deps → Update dependencies (Step 7: Creating MR)
   ```
4. `cd` into chosen worktree and continue from state.md

### Pipeline Rollback

When a pipeline step fails irrecoverably (e.g., 3 CI failures, merge conflict that can't be resolved):

1. **Before worktree cleanup:** save `state.md` and `findings.md` to `tmp/flowyeah/aborted/<key>/` for post-mortem
2. **Reset the plan task:** uncheck `[x]` → `[ ]` in `tmp/flowyeah/plans/<key>.md` if it was prematurely marked
3. **Clean up remote:** delete the remote branch if the PR was already created but not merged
4. **Clean up worktree:** remove with `git worktree remove`
5. **Report:** summarize what happened, what was saved, and what the user should do next

The aborted session artifacts in `tmp/flowyeah/aborted/` persist until manually deleted, so the user can review what went wrong.

### Session End (step 8-9)

Before worktree cleanup:
1. Read `findings.md` and identify insights worth keeping
2. Promote qualified findings to auto memory (MEMORY.md or topic files)
3. Worktree removal in step 9 deletes the `.flowyeah/` directory

## Parallel Coordination

Before claiming a task, check if another instance is already working on it:
1. `git branch -a | grep -E 'feat/|fix/|refactor/|chore/'`
2. Branch with task slug exists → task claimed → pick next
3. Creating branch = claiming the task

## Task Sizing

One task = one reasonable PR. If a task is too large:
1. Brainstorm/plan the task
2. Decompose into subtasks in `tmp/flowyeah/plans/<key>.md`
3. Execute first subtask
4. Next iteration picks next subtask

## Project Configuration — `flowyeah.yml`

All project conventions live in `flowyeah.yml` at the project root (versioned).

**Precedence:** `flowyeah.yml` overrides CLAUDE.md for all flowyeah operations. If flowyeah.yml says `default_branch: develop` and CLAUDE.md says something else, flowyeah.yml wins.

### First Run (no `flowyeah.yml`)

If `flowyeah.yml` does not exist, load `setup.md` from the plugin root and follow its interactive setup instructions. Then proceed with the pipeline.

### Schema

```yaml
version: 1                          # config schema version — bump when making breaking changes

# ── Core pipeline config (schema-defined) ──

language: pt-br                   # used for commits, PRs, and review comments

git:
  default_branch: develop

testing:
  command: bundle exec rspec
  scope: related                  # related | full

commits:
  conventions: conventional       # conventional | freeform
  writer: git-commit-writer       # agent name, or null for manual

pull_requests:
  delete_source_branch: true
  rebase: true
  merge: auto                     # auto | manual | ask
  merge_strategy: squash          # squash | merge | rebase

code_review:
  agents:                         # always run these
    - pr-review-toolkit:code-reviewer
    - pr-review-toolkit:silent-failure-hunter
  optional_agents:                # AI decides based on what changed
    - pr-review-toolkit:comment-analyzer
    - pr-review-toolkit:type-design-analyzer

issues:
  create_when_missing: ask        # ask | always | never
  adapter: gitlab                 # which adapter handles issue creation — points to adapters.<adapter>

# ── Adapters: connection config per integration, each adapter owns its keys ──

adapters:
  gitlab:                         # loads adapters/gitlab/{connection,source,hosting,review}.md
    url: https://gitlab.example.com
    token_env: GITLAB_TOKEN
    token_source: .env
    project_id: 123
  github:                         # loads adapters/github/{connection,source,hosting,review}.md
    # github uses gh CLI — no extra config needed
  linear:                         # loads adapters/linear/{connection,source}.md
    # linear uses MCP — no extra config needed
  bugsink:                        # loads adapters/bugsink/{connection,source}.md
    url: https://bugsink.example.com
    token_env: BUGSINK_TOKEN
    token_source: .env
  newrelic:                       # loads adapters/newrelic/{connection,source}.md
    token_env: NEW_RELIC_API_KEY
    token_source: .env
    account_id: 12345

# ── Sources: which adapters can be used as input ──

sources:                            # list of adapter keys usable as sources
  - gitlab
  - github
  - linear
  - bugsink
  - newrelic

# ── Hosting: which adapter handles PR/MR creation ──

hosting: gitlab                   # gitlab | github — points to adapters.<hosting>
```

### Defaults (when key is absent)

| Key | Default |
|-----|---------|
| `language` | `en` |
| `git.default_branch` | `main` |
| `sources` | All adapter keys that have a `source.md` |
| `hosting` | **Required — STOP if missing. Must be an adapter that has a `hosting.md` file.** |
| `testing.scope` | `related` |
| `commits.conventions` | `conventional` |
| `commits.writer` | `null` (manual) |
| `pull_requests.delete_source_branch` | `true` |
| `pull_requests.rebase` | `true` |
| `pull_requests.merge` | `manual` |
| `pull_requests.merge_strategy` | `squash` |
| `code_review.agents` | **None — STOP and complain if empty** |
| `issues.create_when_missing` | `ask` |
| `issues.adapter` | **Required when `create_when_missing` is `ask` or `always`. Must be an adapter that has a `source.md` file.** |

### Adapters

Adapters live in `adapters/` at the plugin level (shared across skills):

```
adapters/
├── gitlab/
│   ├── connection.md    # Auth, base URL, --form encoding
│   ├── source.md        # Fetch issue → canonical format
│   ├── hosting.md       # Create MR, poll CI, merge
│   └── review.md        # Fetch MR, post formal review
├── github/
│   ├── connection.md    # gh CLI auth
│   ├── source.md        # Fetch issue → canonical format
│   ├── hosting.md       # Create PR, poll CI, merge
│   └── review.md        # Fetch PR, post formal review
├── linear/
│   ├── connection.md    # MCP setup
│   └── source.md        # Fetch issue → canonical format
├── bugsink/
│   ├── connection.md    # API token auth
│   └── source.md        # Fetch error → canonical format
└── newrelic/
    ├── connection.md    # NerdGraph auth
    └── source.md        # Fetch error group → canonical format
```

Each integration directory contains:
- **`connection.md`** — shared authentication, base URL, encoding conventions
- **`source.md`** — fetch data and convert to canonical format
- **`hosting.md`** — create PR/MR, poll CI, merge
- **`review.md`** — fetch PR/MR details, post formal review with inline comments

The core skill reads the adapter and follows its instructions. **Config lookup rule:** all adapter config is always under `adapters.<name>` in `flowyeah.yml`, regardless of whether the adapter is used as a source, hosting, or both. Adapter-specific config keys are schema-free — each adapter defines and validates its own keys.

**Adding a new integration:** create an adapter directory with `connection.md` + the adapter types you need, add config to `flowyeah.yml`. No changes to core skills.

## Stop Conditions

**STOP immediately and ask when:**

| Condition | Action |
|-----------|--------|
| Ambiguous task | Present interpretations, ask |
| No tasks remaining | Report plan status |
| Tests fail 3x | Show failures, ask for guidance |
| Architectural decision needed | Present options, ask |
| Missing dependency | State what's needed |
| No code review agents | STOP and complain |

**When stopping, always provide:**
1. What you were trying to do
2. What went wrong or is unclear
3. What you've already tried (if applicable)
4. Specific question — not "what should I do?" but "should I use approach A or B?"

## Never

- Write code outside a worktree (analysis and planning OK, code changes NOT)
- Skip code review to make progress
- Implement workarounds instead of asking
- Accept "good enough" implementations
- Ignore test failures, warnings, or errors
- Assume requirements when unsure
- Give back the prompt during CI wait
