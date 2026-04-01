---
name: status
description: Show active sessions, plans, and worktrees. Use with `clean` to remove stale artifacts interactively.
---

# flowyeah:status — Project Health Overview

Shows all active flowyeah sessions, plans, and worktrees. With `clean`, offers interactive removal of stale artifacts.

```
flowyeah:status
flowyeah:status clean
```

## Prerequisites

`flowyeah.yml` must exist in the project root. If missing, report and exit — there's nothing to show.

Must run from the main checkout (not inside a worktree). If `git rev-parse --show-toplevel` contains `.flowyeah/worktrees/`, STOP: "Run from the main checkout, not from inside a worktree."

## `flowyeah:status` (read-only)

Scan and report. No file mutations, no interactive questions beyond displaying results.

### 1. Active Sessions

Scan for all session types and display a unified table.

**Build sessions:**

```bash
shopt -s nullglob
for state_file in .flowyeah/worktrees/*/.flowyeah/state.md; do
  # Extract: worktree name, task, step, mode, plan, branch
done
shopt -u nullglob
```

**Review sessions:**

```bash
shopt -s nullglob
for state_file in .flowyeah/review-state-*.md; do
  # Extract: PR number, branch, phase, mode, findings count
done
shopt -u nullglob
```

**Respond sessions:**

```bash
if [ -f .flowyeah/respond-state.md ]; then
  # Extract: PR number, branch, phase, comments count
fi
```

**Output format:**

```
Active Sessions
───────────────────────────────────────────────────────────

  Build:
    feat-5588        → Webhook retry logic (Step 4: TDD, continuous)
    fix-5590         → Payment validation (Step 7b: CI wait)

  Review:
    PR #42           → feat/login-redesign (Phase: Interactive Approval, 5 findings)

  Respond:
    PR #38           → fix/null-check (Phase: Implementing, 3 comments)

  Total: 4 active sessions
```

If no sessions of a type, omit that section. If no sessions at all: "No active sessions."

### 2. Plans

Scan `tmp/flowyeah/plans/` and classify each plan.

```bash
shopt -s nullglob
for plan in tmp/flowyeah/plans/*.md; do
  TOTAL=$(grep -c '^\- \[' "$plan" 2>/dev/null || echo 0)
  DONE=$(grep -c '^\- \[x\]' "$plan" 2>/dev/null || echo 0)
  REMAINING=$((TOTAL - DONE))
  MODIFIED=$(stat -c %Y "$plan" 2>/dev/null || stat -f %m "$plan" 2>/dev/null)
done
shopt -u nullglob
```

**Classification:**

| Status | Condition |
|--------|-----------|
| Completed | All tasks `[x]` |
| Active | Unchecked tasks remain, matching branch exists |
| Stale | Unchecked tasks remain, no matching branch, last modified >30 days ago |

**Output format:**

```
Plans
───────────────────────────────────────────────────────────

  ✅ gitlab-5588.md          4/4 tasks done    (completed 3 days ago)
  🔧 github-45.md            2/5 tasks done    (active — branch feat/45)
  ⬚  bugsink-68b87507.md     0/3 tasks done    (stale — no branch, 45 days old)

  Total: 3 plans (1 completed, 1 active, 1 stale)
```

If no plans: "No plans in tmp/flowyeah/plans/."

### 3. Aborted Sessions

Scan `tmp/flowyeah/aborted/` for post-mortem artifacts.

```bash
shopt -s nullglob
for dir in tmp/flowyeah/aborted/*/; do
  KEY=$(basename "$dir")
  MODIFIED=$(stat -c %Y "$dir/state.md" 2>/dev/null || stat -f %m "$dir/state.md" 2>/dev/null)
done
shopt -u nullglob
```

**Output format:**

```
Aborted Sessions
───────────────────────────────────────────────────────────

  gitlab-5590/     state.md + findings.md    (aborted 12 days ago)

  Total: 1 aborted session
```

If none: omit section.

### 4. Worktrees

List flowyeah-managed worktrees and their disk usage.

```bash
shopt -s nullglob
for wt in .flowyeah/worktrees/*/; do
  NAME=$(basename "$wt")
  SIZE=$(du -sh "$wt" 2>/dev/null | cut -f1)
  HAS_SESSION=$([ -f "$wt/.flowyeah/state.md" ] && echo "active" || echo "orphaned")
done
shopt -u nullglob
```

**Output format:**

```
Worktrees
───────────────────────────────────────────────────────────

  feat-5588/       128M    (active session)
  fix-5590/        96M     (active session)
  chore-deps/      84M     (orphaned — no session file)

  Total: 3 worktrees, 308M disk usage
```

If none: "No flowyeah worktrees."

### 5. Summary

```
═══════════════════════════════════════════════════════════
Status: 4 sessions, 3 plans, 1 aborted, 3 worktrees (308M)

Cleanable: 1 completed plan, 1 stale plan, 1 aborted session, 1 orphaned worktree
Run `flowyeah:status clean` to remove stale artifacts.
═══════════════════════════════════════════════════════════
```

If nothing is cleanable, omit the "Cleanable" line and the suggestion.

---

## `flowyeah:status clean` (destructive)

Runs the full read-only status first (sections 1-5 above), then offers interactive cleanup for each category of stale artifacts.

### Cleanup Categories

Process each category in order. For each, show what would be removed and ask for confirmation.

**1. Completed plans** (all tasks `[x]`):

```
Completed plans to remove:
  - tmp/flowyeah/plans/gitlab-5588.md (4/4 tasks, completed 3 days ago)
  - tmp/flowyeah/plans/github-12.md (2/2 tasks, completed 10 days ago)

Remove 2 completed plans? (yes/no)
```

**2. Stale plans** (unchecked tasks, no matching branch, >30 days old):

```
Stale plans to remove:
  - tmp/flowyeah/plans/bugsink-68b87507.md (0/3 tasks, no branch, 45 days old)

Remove 1 stale plan? (yes/no)
```

**3. Aborted sessions** (>30 days old):

```
Aborted sessions to remove:
  - tmp/flowyeah/aborted/gitlab-5590/ (aborted 35 days ago)

Remove 1 aborted session? (yes/no)
```

**4. Orphaned worktrees** (no session file inside):

```
Orphaned worktrees to remove:
  - .flowyeah/worktrees/chore-deps/ (84M, no session file)

Remove 1 orphaned worktree? (yes/no)
```

For worktrees, follow the **Teardown** procedure from `worktree-lifecycle.md` before removal (close IDE windows, run teardown commands if env vars are recoverable from config, then `git worktree remove`).

**5. Stale review/respond state files** (branch no longer exists):

```bash
for state_file in .flowyeah/review-state-*.md .flowyeah/respond-state.md; do
  BRANCH=$(grep -m1 '^Branch:' "$state_file" 2>/dev/null | cut -d' ' -f2-)
  # Check if branch exists locally or remotely
  git show-ref --verify --quiet "refs/heads/$BRANCH" 2>/dev/null || \
  git show-ref --verify --quiet "refs/remotes/origin/$BRANCH" 2>/dev/null || \
  echo "stale"
done
```

```
Stale state files to remove:
  - .flowyeah/review-state-42.md (branch feat/login-redesign gone)

Remove 1 stale state file? (yes/no)
```

### Cleanup Rules

- **Each category is confirmed independently.** The user can say yes to plans and no to worktrees.
- **TWO-TURN STOP per category.** Ask in one turn, act on the answer in the next. Same protocol as `pull_requests.merge: ask` in the build skill.
- **Completed plans have no age threshold in clean mode.** The build skill's 7-day auto-cleanup only applies to background lifecycle checks. When the user explicitly runs `clean`, all completed plans are offered for removal.
- **Stale plans keep the 30-day threshold.** Plans with unchecked tasks that are younger than 30 days might still be relevant.
- **Aborted sessions keep the 30-day threshold.** Recent aborted sessions may still be useful for post-mortem.
- **Active sessions are never offered for cleanup.** If a worktree has a session file, it's active — skip it.
- **Never force-remove worktrees.** If `git worktree remove` fails (uncommitted changes), report the error and skip.

### Summary

After all categories are processed:

```
Clean complete:
  Removed: 2 plans, 1 aborted session, 1 worktree (84M freed)
  Skipped: 1 stale state file (user declined)
```

## Error Handling

| Error | Action |
|-------|--------|
| Not in a git repo | Report and exit |
| No `flowyeah.yml` | Report and exit |
| Inside a worktree | Report and exit |
| `tmp/` directory missing | Skip plans/aborted sections |
| `.flowyeah/` directory missing | Skip sessions/worktrees sections |
| `stat` not available | Skip age calculations, show "age unknown" |
| Worktree removal fails | Report error, skip, continue with next |
