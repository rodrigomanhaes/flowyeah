# GitHub Connection

Shared authentication and conventions for all GitHub adapters.

## Required Config (`flowyeah.yml`)

```yaml
adapters:
  github:
    # github uses gh CLI — no extra config needed
```

No adapter-specific config needed — `gh` uses the local git remote and GitHub authentication.

## Authentication

The `gh` CLI handles authentication. Verify:

```bash
gh auth status
```

If not authenticated, ask the user to run `gh auth login`.

## API Access

For operations not available through `gh` CLI subcommands, use the GitHub API directly:

```bash
gh api repos/{owner}/{repo}/endpoint
```

Detect owner/repo automatically:

```bash
gh repo view --json owner,name --jq '"\(.owner.login)/\(.name)"'
```

## Detecting GitHub

When auto-detecting the platform from the git remote:

```bash
git remote get-url origin | grep -qi 'github.com'
```

## Write Operations Safety

Every write (creating PRs, issues, comments, reviews; merging; editing assignees, labels, reviewers) creates or mutates real shared state on GitHub. Follow these rules in `source.md`, `hosting.md`, `review.md`, and `respond.md`.

**See also: `../_shared/write-safety.md`** for the transversal principle (parsing failure ≠ operation failure; verify before retry). The rules below implement it for `gh` and `gh api`.

### Multi-line bodies go via `--body-file`

PR descriptions, issue bodies, and review comments are typically multi-line markdown. Pass them via `--body-file`, never via `--body "$VAR"`:

```bash
# Correct
cat > "$TMPDIR_FY/pr-body.md" <<'EOF'
## Summary
- multi-line content with `code`, $vars, "quotes" all safe
EOF
gh pr create --title "<title>" --body-file "$TMPDIR_FY/pr-body.md" --base main

# Avoid
BODY=$(cat ...)
gh pr create --title "<title>" --body "$BODY" --base main
```

`$VAR` in shell loses information across quoting boundaries (backticks, `$`, embedded newlines) and is the same fragility class that caused the duplicate-issue incident on GitLab.

For `gh api` POST/PUT with a JSON body, use `--input file.json` (or `--input -` with stdin):

```bash
jq -n --arg title "$TITLE" --arg body "$(cat "$TMPDIR_FY/issue-body.md")" \
  '{title: $title, body: $body}' \
  | gh api repos/<owner>/<repo>/issues --input - > "$TMPDIR_FY/resp.json"
```

### Capture response, then parse

Don't pipe `gh api` POST/PUT/DELETE output straight into `--jq` or another parser. Redirect to a file first so the response survives a parsing failure:

```bash
# Correct
gh api repos/<owner>/<repo>/issues --method POST --input "$TMPDIR_FY/payload.json" \
  > "$TMPDIR_FY/resp.json"
jq -r '.number, .html_url' "$TMPDIR_FY/resp.json"

# Avoid — if the parser barfs, the response is gone
gh api repos/<owner>/<repo>/issues --method POST --input "$TMPDIR_FY/payload.json" \
  --jq '.number'
```

Use per-session paths (`$TMPDIR_FY` or `$(mktemp -d)`); never hardcode `/tmp/resp.json` (parallel `flowyeah:respond` sessions would collide).

### Parsing failure does not mean operation failure

If `gh pr create`, `gh issue create`, or `gh api ... POST/PUT/DELETE` errors after the request was sent (timeout, broken pipe, parsing failure on the response), **the write may have succeeded**. Do not retry blindly.

Verify state before retrying:

```bash
# PRs — exact title match within the current repo
TITLE="<exact title that was sent>"
gh pr list --search "\"$TITLE\" in:title" --state open \
  --json number,title,url | \
  jq --arg t "$TITLE" '[.[] | select(.title == $t)]'

# Issues
gh issue list --search "\"$TITLE\" in:title" --state open \
  --json number,title,url | \
  jq --arg t "$TITLE" '[.[] | select(.title == $t)]'
```

- Empty array → safe to retry.
- One match → record the number and continue.
- Multiple matches → STOP and ask.

For review comments, verify via `gh api repos/<owner>/<repo>/pulls/<n>/comments` filtered by author + body substring before reposting the same comment.
