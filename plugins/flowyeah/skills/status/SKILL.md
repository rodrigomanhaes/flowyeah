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

Must run from the main checkout (not inside a worktree). If `git rev-parse --show-toplevel` contains `.flowyeah/worktrees/` or `.flowyeah/review-worktrees/`, STOP: "Run from the main checkout, not from inside a worktree."

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
shopt -s nullglob
for state_file in .flowyeah/respond-state-*.md; do
  # Extract: PR number (from filename), branch, phase, item count
done
shopt -u nullglob
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
    PR #44           → feat/webhook-v2 (Phase: Responded, round closed)

  Respond:
    PR #38           → fix/null-check (Phase: Implementing, 3 items)
    PR #45           → feat/webhook-v2 (--own mode, Phase: Interactive Triage, 6 findings)

  Total: 5 active sessions
```

If no sessions of a type, omit that section. If no sessions at all: "No active sessions."

### 2. Plans

Scan `tmp/flowyeah/plans/` and classify each plan.

```bash
shopt -s nullglob
for plan in tmp/flowyeah/plans/*.md; do
  # Indentation-tolerant: nested subtasks count too (canonical plan format
  # nests leaves with 2-space indentation)
  TOTAL=$(grep -c '^[[:space:]]*- \[' "$plan" 2>/dev/null || echo 0)
  DONE=$(grep -c '^[[:space:]]*- \[x\]' "$plan" 2>/dev/null || echo 0)
  REMAINING=$((TOTAL - DONE))
  MODIFIED=$(stat -c %Y "$plan" 2>/dev/null || stat -f %m "$plan" 2>/dev/null)
done
shopt -u nullglob
```

**Classification:**

| Status | Condition |
|--------|-----------|
| Completed | All tasks `[x]`, at any nesting depth |
| Active | Unchecked tasks remain, matching branch exists |
| Stale | Unchecked tasks remain, no matching branch, last modified >30 days ago |
| Pending | Unchecked tasks remain, no matching branch, last modified ≤30 days ago — displayed, never offered for cleanup |

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

List flowyeah-managed worktrees and their disk usage. Two locations: `.flowyeah/worktrees/` (build and respond) and `.flowyeah/review-worktrees/` (review).

A worktree is **active** when any session owns it — ownership has three signals, and all three must be checked before calling a worktree orphaned:

1. **Build:** `state.md` inside the worktree (`<wt>/.flowyeah/state.md`)
2. **Respond:** the worktree path appears in the `Worktree:` field of any `.flowyeah/respond-state-*.md` at the main checkout (respond sessions keep their state at the main checkout, not inside the worktree)
3. **Review:** for `.flowyeah/review-worktrees/{N}/`, a `.flowyeah/review-state-{N}.md` exists (the directory is named after the PR number)

```bash
shopt -s nullglob
for wt in .flowyeah/worktrees/*/; do
  NAME=$(basename "$wt")
  SIZE=$(du -sh "$wt" 2>/dev/null | cut -f1)
  STATUS="orphaned"
  if [ -f "$wt/.flowyeah/state.md" ]; then
    STATUS="active (build)"
  else
    for sf in .flowyeah/review-state-*.md .flowyeah/respond-state-*.md; do
      WT_REF=$(grep -m1 '^Worktree:' "$sf" 2>/dev/null | sed -e 's/^Worktree:[[:space:]]*//' -e 's/[[:space:]]*$//')
      case "$WT_REF" in
        *"worktrees/$NAME"*) STATUS="active (session ${sf##*/})"; break ;;
      esac
    done
  fi
done

for wt in .flowyeah/review-worktrees/*/; do
  N=$(basename "$wt")
  SIZE=$(du -sh "$wt" 2>/dev/null | cut -f1)
  STATUS=$([ -f ".flowyeah/review-state-${N}.md" ] && echo "active (review PR #$N)" || echo "orphaned")
done
shopt -u nullglob
```

**Output format:**

```
Worktrees
───────────────────────────────────────────────────────────

  worktrees/feat-5588/          128M    (active — build session)
  worktrees/fix-5590/           96M     (active — respond-state-38.md)
  worktrees/chore-deps/         84M     (orphaned — no owning session)
  review-worktrees/42/          64M     (active — review PR #42)

  Total: 4 worktrees, 372M disk usage
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

**4. Orphaned worktrees** (no owning session per the three ownership signals in section 4 — in-worktree `state.md`, `Worktree:` reference in any review/respond state file, or `review-state-{N}.md` for a review worktree):

```
Orphaned worktrees to remove:
  - .flowyeah/worktrees/chore-deps/ (84M, no owning session)
  - .flowyeah/review-worktrees/17/ (52M, no review-state-17.md)

Remove 2 orphaned worktrees? (yes/no)
```

For worktrees, follow the **Teardown** procedure from `worktree-lifecycle.md` before removal (close IDE windows, then `git worktree remove`). Skip `worktree.teardown` commands for orphans: their env values lived in the session state file that no longer exists and cannot be reconstructed from config (`auto` entries are random per worktree) — warn the user that resources created by `worktree.setup` (e.g. per-worktree databases) may linger and need manual cleanup.

**5. Stale review/respond state files** (branch no longer exists):

```bash
shopt -s nullglob
for state_file in .flowyeah/review-state-*.md .flowyeah/respond-state-*.md; do
  BRANCH=$(grep -m1 '^Branch:' "$state_file" 2>/dev/null | cut -d' ' -f2-)
  # Check if branch exists locally or remotely
  git show-ref --verify --quiet "refs/heads/$BRANCH" 2>/dev/null || \
  git show-ref --verify --quiet "refs/remotes/origin/$BRANCH" 2>/dev/null || \
  echo "stale"
done
shopt -u nullglob
```

Removing a stale state file removes its companions in the same action — a state file is the only handle the other files have, so leaving them behind makes them permanently unreachable:

- `review-state-{N}.md` → also `review-approved-{N}.md` and `own-rejections-{N}.md` (if present) — same set as `/flowyeah:review finalize`
- `respond-state-{N}.md` → also `respond-decisions-{N}.md` (if present)

```
Stale state files to remove:
  - .flowyeah/review-state-42.md (branch feat/login-redesign gone)
    + review-approved-42.md, own-rejections-42.md

Remove 1 stale state file (and 2 companions)? (yes/no)
```

**5b. Orphaned companion files** (no matching state file):

```bash
shopt -s nullglob
for f in .flowyeah/own-rejections-*.md .flowyeah/review-approved-*.md; do
  number="${f##*-}"; number="${number%.md}"
  [ -f ".flowyeah/review-state-${number}.md" ] || echo "orphaned: $f"
done
for f in .flowyeah/respond-decisions-*.md; do
  number="${f##*respond-decisions-}"; number="${number%.md}"
  [ -f ".flowyeah/respond-state-${number}.md" ] || echo "orphaned: $f"
done
shopt -u nullglob
```

```
Orphaned companion files to remove:
  - .flowyeah/own-rejections-42.md (no review session)
  - .flowyeah/respond-decisions-38.md (no respond session)

Remove 2 orphaned files? (yes/no)
```

This catches sessions torn down outside their own cleanup path (e.g., a manually deleted state file). It does **not** fire while the owning state file for that PR is still on disk — `own-rejections-{N}.md` in particular is intentionally long-lived during an active review relationship.

**6. Closed review rounds** (`Phase: Responded`, no pending respond state):

```bash
shopt -s nullglob
for state_file in .flowyeah/review-state-*.md; do
  PHASE=$(grep -m1 '^Phase:' "$state_file" 2>/dev/null | cut -d' ' -f2-)
  if [ "$PHASE" = "Responded" ]; then
    NUMBER="${state_file##*review-state-}"
    NUMBER="${NUMBER%.md}"
    if [ ! -f ".flowyeah/respond-state-${NUMBER}.md" ]; then
      # candidate for clean
      :
    fi
  fi
done
shopt -u nullglob
```

```
Closed review rounds to finalize:
  - .flowyeah/review-state-42.md (Phase: Responded, no active respond)

Finalize 1 closed review round? (yes/no)
```

"Finalize" here means running the same teardown as `/flowyeah:review finalize {N}` (see the finalize subcommand in `skills/review/SKILL.md`): if the state file's `Worktree:` field is set and not `none`, remove that review worktree first (`git worktree remove --force`, then `rm -rf` if the directory survives), then delete `review-state-{N}.md`, `review-approved-{N}.md`, `own-rejections-{N}.md`, and any leftover `respond-state-{N}.md`/`respond-decisions-{N}.md`. Not a destructive operation on the PR itself.

### Cleanup Rules

- **Each category is confirmed independently.** The user can say yes to plans and no to worktrees.
- **TWO-TURN STOP per category.** Ask in one turn, act on the answer in the next. Same protocol as `pull_requests.merge: ask` in the build skill.
- **Completed plans have no age threshold in clean mode.** The build skill's 7-day auto-cleanup only applies to background lifecycle checks. When the user explicitly runs `clean`, all completed plans are offered for removal.
- **Stale plans keep the 30-day threshold.** Plans with unchecked tasks that are younger than 30 days might still be relevant.
- **Aborted sessions keep the 30-day threshold.** Recent aborted sessions may still be useful for post-mortem.
- **Active sessions are never offered for cleanup.** A worktree is active if any of the three ownership signals from section 4 matches (in-worktree `state.md`, `Worktree:` reference in a review/respond state file, or `review-state-{N}.md` for a review worktree) — skip it. When in doubt about ownership, skip: deleting a live worktree destroys uncommitted work.
- **Never force-remove worktrees.** If `git worktree remove` fails (uncommitted changes), report the error and skip.
- **`Phase: Responded` is safe-to-finalize when no active respond session exists.** The round is complete; the review relationship may still have future rounds, so finalization is the user's call, not automatic.

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
