# GitHub Hosting Adapter

Creates pull requests, polls CI, and merges via the `gh` CLI.

**Connection:** See `connection.md` for authentication.

## Create or Reuse Pull Request

### Check for Existing PR

Before creating, check if a PR already exists for this branch:

```bash
gh pr view <source_branch> --json number,url,title,state 2>/dev/null
```

- **Command succeeds and `state` is `OPEN`** → PR already exists. Reuse it — save `number` and `url`, skip creation.
- **Command succeeds with `MERGED` or `CLOSED`** → that PR is dead; proceed with creation. (`gh pr view <branch>` returns the most recent PR for the branch even when it is not open.)
- **Command fails** → no PR exists, proceed with creation.

### Create PR

The body is multi-line markdown — pass it via `--body-file`, never inline (see the "Multi-line strings" rule in `connection.md`):

```bash
TMPDIR_FY="${TMPDIR_FY:-$(mktemp -d)}"
# write <body> to "$TMPDIR_FY/pr-body.md" first
gh pr create \
  --title "<title>" \
  --body-file "$TMPDIR_FY/pr-body.md" \
  --base "<target_branch>" \
  --head "<source_branch>" \
  --assignee "@me"
```

**Capture the PR URL** from `gh pr create` output for later reference.

If `delete_source_branch` is true, the branch is deleted after merge (handled by the merge step).

## Poll CI Status

```bash
gh pr checks <source_branch> --watch --fail-fast
```

This blocks until all checks complete. If any check fails, the command exits with a non-zero status.

**Alternative (non-blocking poll):**

```bash
gh pr checks <source_branch> --json name,bucket | \
  jq '.[] | select(.bucket == "pending")'
```

- Empty output → all checks completed
- Check `bucket`: `pass`, `fail`, `skipping`, `cancel`

**Poll interval (if not using `--watch`):** 30 seconds. **Timeout:** after 10 minutes, ask the user.

### Reading CI Failure Details

```bash
gh pr checks <source_branch> --json name,bucket,link | \
  jq '.[] | select(.bucket == "fail")'
```

Use the `link` to understand what failed. For GitHub Actions:

```bash
gh run view <run_id> --log-failed
```

## Merge

For `squash` and `merge` strategies (a merge/squash commit exists to message — its body is multi-line, so use `--body-file`):

```bash
TMPDIR_FY="${TMPDIR_FY:-$(mktemp -d)}"
# write <PR description> to "$TMPDIR_FY/merge-body.md" first
gh pr merge <source_branch> --<merge_strategy> \
  --subject "<PR title>" --body-file "$TMPDIR_FY/merge-body.md" \
  --delete-branch
```

For `rebase` there is no merge commit to message — gh rejects `--subject`/`--body` with `--rebase`, so omit them:

```bash
gh pr merge <source_branch> --rebase --delete-branch
```

Flags:
- `--<merge_strategy>` — read from `pull_requests.merge_strategy`: `--squash`, `--merge`, or `--rebase`
- `--subject` / `--body-file` — set the merge commit message to the PR title + description (squash/merge only)
- `--delete-branch` — remove source branch after merge (if `delete_source_branch` is true)
- Without `--delete-branch` if `delete_source_branch` is false

If merge fails (e.g., conflicts, required reviews), report the error and ask the user.

## Update PR (optional)

If you need to update the PR after pushing fixes:

```bash
TMPDIR_FY="${TMPDIR_FY:-$(mktemp -d)}"
# write the new body to "$TMPDIR_FY/pr-body.md" first (only when changing it)
gh pr edit <number> --title "<new_title>" --body-file "$TMPDIR_FY/pr-body.md"
```

## Issue Linking

When the source was a GitHub issue, include `Closes #<issue_number>` in the PR body. GitHub auto-closes the issue on merge.

For PR title, append `(#<issue_number>)` at the end.

## Issue Assignment

When an issue is associated with this PR (either from the source or created via `issues.create_when_missing`), assign the issue to the current user:

```bash
gh issue edit <issue_number> --add-assignee "@me"
```
