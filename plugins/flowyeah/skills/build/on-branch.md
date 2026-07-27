# `--on-branch <branch>` — attach to an existing branch

Reached from step 3 of `flowyeah:build` when `--on-branch` is passed. Replaces the normal branch creation flow: the branch already exists, so the pipeline attaches to it instead of making one.

Skip branch naming, type inference, and issue claiming — the branch and any associated issue are already set up.

```bash
git fetch origin <branch>

SLUG=$(printf '%s' "<branch>" | tr '/' '-')

# Locate a worktree that already has this branch checked out (exact ref match)
EXISTING=$(git worktree list --porcelain | awk -v ref="refs/heads/<branch>" \
  '/^worktree /{wt=substr($0,10)} $0=="branch "ref{print wt; exit}')

if [ -n "$EXISTING" ]; then
  case "$EXISTING" in
    */.flowyeah/worktrees/*)
      # Reuse the worktree from a previous session
      cd "$EXISTING"
      ;;
    *)
      # Checked out in the primary or a user-managed worktree — STOP (see below)
      ;;
  esac
elif git show-ref --verify --quiet "refs/heads/<branch>"; then
  # Local branch exists but is checked out nowhere. Refuse stale state:
  # fast-forward if strictly behind origin, STOP if diverged (see below).
  BEHIND=$(git rev-list --count "<branch>..origin/<branch>" 2>/dev/null || echo 0)
  AHEAD=$(git rev-list --count "origin/<branch>..<branch>" 2>/dev/null || echo 0)
  if [ "$BEHIND" -gt 0 ] && [ "$AHEAD" -eq 0 ]; then
    git branch -f <branch> origin/<branch>
  fi
  git worktree add ".flowyeah/worktrees/$SLUG" <branch>
  cd ".flowyeah/worktrees/$SLUG"
else
  # No local branch — create one tracking the remote
  git worktree add ".flowyeah/worktrees/$SLUG" -b <branch> --track origin/<branch>
  cd ".flowyeah/worktrees/$SLUG"
fi
```

- **No new remote branch is ever created** — `--on-branch` only attaches to a branch that already exists (a local tracking branch may be created for a remote-only branch).
- **Worktree reuse** — only worktrees under `.flowyeah/worktrees/` are reused. If the branch is checked out in the primary checkout or a user-managed worktree, **STOP** and report: git refuses a second checkout of the same branch, and mutating a checkout the pipeline doesn't own would violate the invariant. Ask whether to free the branch or work there manually.
- **Diverged local branch** (`BEHIND > 0` and `AHEAD > 0`): **STOP** and ask — fast-forwarding would discard local commits, and rebasing them is the user's decision.
- **Local-only branch** — if `git fetch origin <branch>` reports the remote has no such branch, skip the staleness checks and attach to the local branch directly.
- **Session files** — if `.flowyeah/state.md` exists in the worktree, resume from it (same as crash recovery). If not, create fresh session files with `On-Branch: true` in `state.md`.

After attaching, the rest of step 3 runs normally: worktree verification (3b), symlinks, env setup.

`--intermittent` overrides this flag entirely — see `intermittent.md`.

Rollback interaction: `Pipeline Rollback` skips both branch deletions when `On-Branch: true`, because the branch existed before flowyeah touched it.
