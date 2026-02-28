# GitHub Hosting Adapter

Creates pull requests, polls CI, and merges via the `gh` CLI.

**Connection:** See `connection.md` for authentication.

## Create Pull Request

```bash
gh pr create \
  --title "<title>" \
  --body "<body>" \
  --base "<target_branch>" \
  --head "<source_branch>"
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
gh pr checks <source_branch> --json name,state,conclusion | \
  jq '.[] | select(.state != "COMPLETED")'
```

- Empty output → all checks completed
- Check `conclusion`: `SUCCESS`, `FAILURE`, `NEUTRAL`, `SKIPPED`

**Poll interval (if not using `--watch`):** 30 seconds. **Timeout:** after 10 minutes, ask the user.

### Reading CI Failure Details

```bash
gh pr checks <source_branch> --json name,state,conclusion,detailsUrl | \
  jq '.[] | select(.conclusion == "FAILURE")'
```

Use the `detailsUrl` to understand what failed. For GitHub Actions:

```bash
gh run view <run_id> --log-failed
```

## Merge

```bash
gh pr merge <source_branch> --<merge_strategy> \
  --subject "<PR title>" --body "<PR description>" \
  --delete-branch
```

Flags:
- `--<merge_strategy>` — read from `pull_requests.merge_strategy`: `--squash`, `--merge`, or `--rebase`
- `--subject` / `--body` — set the merge commit message to the PR title + description (instead of GitHub's default)
- `--delete-branch` — remove source branch after merge (if `delete_source_branch` is true)
- Without `--delete-branch` if `delete_source_branch` is false

If merge fails (e.g., conflicts, required reviews), report the error and ask the user.

## Issue Linking

When the source was a GitHub issue, include `Closes #<issue_number>` in the PR body. GitHub auto-closes the issue on merge.

For PR title, append `(#<issue_number>)` at the end.
