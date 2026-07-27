# Invariant: Primary Checkout Is Untouched

Shared by `flowyeah:build`, `flowyeah:review`, and `flowyeah:respond`. Each states the rule in its own terms and points here for the detail.

## The rule

Every command that mutates a working tree, an index, or HEAD runs with a flowyeah worktree as its cwd. The checkout the skill was invoked from — the **primary checkout** — stays as the user left it, so they keep it free for unrelated work: deploys, hotfixes, rebases on stable branches.

Against the primary checkout, use read-only commands only:

| Need | Command |
|------|---------|
| PR/MR diff, file list, commits | The skill's adapter API (`gh pr diff <N>`, GitLab diff endpoint) |
| File content at any SHA | `git show <sha>:<file>` |
| Per-line authorship at a SHA | `git blame <sha> -- <file>` |
| File history | `git log --oneline -10 <file>` |
| Recursive symbol search at a SHA | `git grep -n '<symbol>' <sha>` (requires that SHA's objects fetched locally) |
| Ref updates | `git fetch` — refs only, no working-tree side effects |

These cover the great majority of needs. When a skill genuinely needs materialized files — running code at a PR's HEAD, applying a candidate patch, full-tree LSP navigation — it creates its own worktree and works there.

If a step appears to require mutating the primary checkout, STOP and ask the user: the skill is wrong, not your judgment.

## Forbidden in the primary checkout

Reference for what the rule excludes, and the list `tree-guard.sh` enforces:

`git checkout` (including `git checkout <ref> -- <path>`), `git checkout-index`, `git restore`, `git switch`, `git reset`, `git apply`, `git am`, `git merge`, `git rebase`, `git pull`, `git stash`, `git clean`, `git cherry-pick`, `git revert`, `git rm`, `git mv`, `git bisect`.

`git fetch` is allowed — it updates refs and nothing else.

## What tree-guard enforces

`hooks/tree-guard.sh` is a `PreToolUse` hook on `Bash`. It blocks the commands above when they run from the primary checkout while a **review or respond** session is active for the current branch, and stays out of the way inside any worktree under `.flowyeah/worktrees/` or `.flowyeah/review-worktrees/`, in non-flowyeah projects, and on read-only commands.

If it blocks a command, do not retry, escalate, or work around it. Either move the work into the skill's worktree, or stop and ask the user.

Two gaps the agent covers itself:

- **Build sessions are out of scope.** Build pipelines run inside `.flowyeah/worktrees/<name>/` on branches git prevents the primary from sharing, so the build branch is mechanically isolated whatever happens on the primary. Build holds the invariant from inside its worktree.
- **Edit and Write are not hook-gated.** Only `Bash` passes through the hook, so never edit project files outside the worktree — hold that rule deliberately.
