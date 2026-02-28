---
name: review
description: Use when reviewing a pull request or merge request - runs code review agents, validates requirements against issues, checks for critical patterns, and submits formal reviews with inline comments
---

# flowyeah:review — PR/MR Review Pipeline

Reviews a pull request or merge request. Runs review agents, validates requirements, checks for critical patterns, and submits a formal review with inline comments.

```
flowyeah:review [<number>]
```

## Pipeline

```dot
digraph review {
    rankdir=TB;
    node [shape=box];

    identify [label="1. Identify PR/MR"];
    issue [label="1b. Detect Issue"];
    context [label="2. Gather Context"];
    requirements [label="2b. Requirements Validation" shape=diamond];
    agents [label="3. Run Review Agents"];
    checks [label="3b. Critical Checks"];
    score [label="4. Score & Consolidate"];
    approve [label="5. Interactive Approval"];
    type [label="6. Choose Review Type"];
    submit [label="7. Submit Formal Review"];

    identify -> issue -> context;
    context -> requirements;
    requirements -> agents [label="issue found"];
    requirements -> agents [label="no issue\nskip"];
    agents -> checks -> score -> approve -> type -> submit;
}
```

## Configuration

Uses `flowyeah.yml` from the project root. **If missing, load `setup.md` from the plugin root and follow its interactive setup instructions before proceeding.**

```yaml
# Review agents (same as flowyeah:build uses)
code_review:
  agents:
    - pr-review-toolkit:code-reviewer
    - pr-review-toolkit:silent-failure-hunter
  optional_agents:
    - pr-review-toolkit:comment-analyzer
    - pr-review-toolkit:type-design-analyzer

# Sources determine which adapters are available for issue detection
sources:
  - gitlab
  - linear

# Hosting determines the review platform
hosting: gitlab       # gitlab | github — points to adapters.<hosting>

# Language for all text output (commits, PRs, review comments)
language: pt-br
```

**If `code_review.agents` is empty or missing: STOP and complain.**

## Platform Detection

The review adapter is determined from `hosting` in `flowyeah.yml`:

| `hosting` | Review adapter |
|------------|----------------|
| `gitlab` | `adapters/gitlab/review.md` |
| `github` | `adapters/github/review.md` |

Load the review adapter once at the start. **If the hosting adapter has no `review.md`, STOP** — that adapter doesn't support code reviews. All platform-specific operations (fetch PR, post review, detect issue) go through the adapter.

## Session (Lightweight)

**Before creating the review session**, check for active build sessions:

```bash
shopt -s nullglob
SESSIONS=(.flowyeah/worktrees/*/.flowyeah/state.md)
shopt -u nullglob
```

If build worktree sessions exist, **warn the user** and ask whether to proceed. Creating a review session at the project root would make the build worktree sessions invisible to the injection hook.

If running from inside a build worktree, **STOP** — do not create a review `state.md` that would overwrite the build session's state.

Create `.flowyeah/state.md` for compaction resilience:

```markdown
# Current State

Type: review
Status: Reviewing
PR/MR: <number>
Branch: <source_branch>
Platform: <adapter>
Findings: <count> total, <approved> approved
Phase: <current_phase>
```

Update after each phase transition. The hook injection ensures state survives compaction.

No `mission.md`, `progress.md`, or `findings.md` — reviews are short-lived and don't need the full session.

## Steps

### 1. Identify PR/MR

If `<number>` is provided, use it. Otherwise, detect from current branch via the review adapter.

Display PR/MR summary: title, author, branch, additions/deletions, changed files.

### 1b. Detect Associated Issue

Extract issue slug from the branch name. The patterns depend on the project's issue tracking:

**From `flowyeah.yml` `sources` list:**
- If `linear` is in `sources` → try Linear patterns (e.g., `proj-eng-302`, `TEAM-123`)
- If `gitlab` is in `sources` → try GitLab patterns (e.g., leading digits, `feat/42`)
- If `github` is in `sources` → try GitHub patterns (e.g., `feat/42`)

Fetch issue details using the appropriate source adapter (load `adapters/<source>/connection.md` + `adapters/<source>/source.md`).

**If no issue found:** ask the user. If they say "none", skip requirements validation (step 2b).

### 2. Gather Context

Collect in parallel:

1. **PR/MR diff** — via review adapter
2. **Files changed** — via review adapter
3. **Commit messages** — via review adapter
4. **CLAUDE.md files** — find all: global (`~/.claude/CLAUDE.md`), project root, `.claude/CLAUDE.md`, `.claude/standards/*.md`
5. **Git history** — for each changed file: `git log --oneline -10 <file>`

### 2b. Requirements Validation

**Skip if no issue was found in step 1b.**

Analyze in 3 dimensions:

**Completude (Completeness):** Does the implementation cover everything the issue asks for? For each requirement/acceptance criterion in the issue, check if the diff contains corresponding implementation. Generate a finding for unimplemented requirements.

**Pertinência (Scope Creep):** Is there code unrelated to what the issue asks for? Compare changed files/logic against the issue's scope. Use good judgment — refactoring needed for the feature IS pertinent.

**Coerência (Coherence):** Does the implementation approach make sense to solve the described problem? Flag when the implementation seems to solve a different problem than what the issue describes.

### 3. Run Review Agents

Launch agents from `code_review.agents` in parallel using the Task tool:

- Pass each agent the PR diff and changed files
- Each agent returns findings as: file, line, issue, severity, confidence (0-100)

**Conditional agents** from `code_review.optional_agents` — launch based on what changed (e.g., security analyst if auth code was touched). Use judgment.

### 3b. Critical Checks

Run directly (not delegated to agents):

**Database Concurrency:** For any migration adding an index, verify if it should be unique. Application-level validations are NOT sufficient for concurrency — DB constraints are required. If a unique index exists, check for `RecordNotUnique` rescue.

**API Backward Compatibility:** For any migration removing columns, search serializers, API responses, and webhooks. Exposed columns CANNOT be removed — must be deprecated.

**CLAUDE.md Compliance:** Check global and project CLAUDE.md rules against the diff (e.g., ABOUTME comments, naming conventions, error handling).

**Naming Consistency:** Flag semantic inconsistencies — names that contradict each other, method names that don't match behavior.

### 4. Score & Consolidate

**Confidence scoring (0-100):**

| Score | Meaning |
|-------|---------|
| 0 | False positive |
| 25 | Might be real, couldn't verify. Stylistic issue not in CLAUDE.md |
| 50 | Verified real issue, minor or nitpick |
| 75 | Highly confident. Verified, impacts functionality, or explicitly in CLAUDE.md |
| 100 | Absolutely certain. Confirmed, will happen frequently |

**Consolidate findings:**
1. Remove duplicates (same file+line+issue from multiple sources)
2. Sort by severity (blocker first), then by confidence
3. Group by category

**False positive rubric — do NOT flag:**
- Something that looks like a bug but isn't
- Pedantic nitpicks a senior engineer wouldn't mention
- Issues linters/typecheckers/CI will catch
- General quality issues unless explicitly in CLAUDE.md
- Issues silenced with lint-ignore comments
- Missing `frozen_string_literal` in migration files

**"Touched it, own it":** If the PR touches a file (even for refactoring), the author is responsible for issues in that code. Only truly untouched lines are excluded.

### 5. Interactive Approval

For each finding, present to the user:

```
═══════════════════════════════════════════════════════════
Finding [N of TOTAL]
═══════════════════════════════════════════════════════════

Label:      [issue/suggestion/nitpick/...] ([blocking/non-blocking])
Confidence: [score]/100
File:       [path:line]
Source:     [agent/analysis that found it]

Comment (Conventional Comments format):
┌─────────────────────────────────────────────────────────
│ **[label] ([decoration]):** [subject]
│
│ [discussion - context, justification, suggested code]
└─────────────────────────────────────────────────────────
```

**Options:**
1. **Approve** — include in final review
2. **Approve with edit** — modify text before including
3. **Skip** — don't include this finding
4. **Skip all below [severity]** — skip remaining findings below threshold
5. **Stop** — finalize with approved findings so far

### 6. Choose Review Type

After all findings are processed, ask the user:

1. **Request Changes** — formal review requesting changes
2. **Comment** — formal review with comments only
3. **Approve** — approve with observations

### 7. Submit Formal Review

**MANDATORY:** Always submit as a formal platform review with inline comments. Never post a generic timeline comment.

Load the review adapter and follow its instructions to:

1. Build inline comments array (each approved finding with file:line)
2. Build review body (consolidated summary + findings without specific lines)
3. Submit the formal review with the event type chosen in step 6

**All inline comments use [Conventional Comments](https://conventionalcomments.org/) format:**

```
**<label> [decorations]:** <subject>

[discussion]
```

**Labels:** `praise`, `issue`, `suggestion`, `todo`, `question`, `thought`, `nitpick`, `chore`, `note`

**Decorations:** `(blocking)`, `(non-blocking)`, `(if-minor)`

**Include at least one `praise` comment per review** — but never false praise. Look for something to sincerely praise.

Ask for final confirmation before posting.

After posting (or if the user discards), remove `.flowyeah/state.md` to end the session.

### Review Body Template

```markdown
## Code Review

### Requirements Validation
<!-- Only if issue was found -->
**Issue:** [slug](link) — "Issue title"

#### Requirement Coverage
- ✅ Requirement A — implemented in `app/services/...`
- ❌ Requirement B — not found in diff
- ⚠️ Requirement C — partial implementation

### Code Review Summary
[consolidated summary of findings]
```

## Comment Language

Review comments are written in the language configured in `language`. Default: `en`.

## Error Handling

| Error | Action |
|-------|--------|
| PR/MR not found | Ask user for number/URL |
| Agent fails | Report which failed, continue with others |
| Auth failed | Guide to authentication setup |
| Rate limited | Report and suggest waiting |
| Inline comment position not in diff | Move finding to review body |

## Never

- Post without explicit user approval
- Include findings the user skipped
- Use `gh pr review --comment --body` (that's not an inline review)
- Post a generic timeline comment instead of a formal review
- Skip the review type question
- Submit a review without inline comments (when there are approved findings with file:line)
