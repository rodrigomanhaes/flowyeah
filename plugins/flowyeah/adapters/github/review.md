# GitHub Review Adapter

Fetches pull request details and submits formal code reviews with inline comments via the GitHub API.

**Connection:** See `connection.md` for authentication.

## Identify the PR

**From a PR number:**

```bash
gh pr view <number> --json number,title,state,headRefName,baseRefName,url,author,additions,deletions,changedFiles,isDraft
```

**From the current branch:**

```bash
gh pr view --json number,title,state,headRefName,baseRefName,url,author,additions,deletions,changedFiles,isDraft
```

## Fetch Diff

```bash
gh pr diff <number>
```

For changed files list:

```bash
gh pr view <number> --json files --jq '.files[].path'
```

## Fetch Commits

```bash
gh pr view <number> --json commits --jq '.commits[] | {oid: .oid, messageHeadline: .messageHeadline}'
```

## Detect Associated Issue

**Extract issue slug from branch name:**

| Pattern | Examples |
|---------|----------|
| `(proj\|projx\|team\|web)-[a-z]+-\d+` (case-insensitive) | `proj-eng-302`, `TEAM-123` |
| Leading digits or `feat/\d+`, `fix/\d+` | `feat/42`, `42-add-pix` |

**Linear issues** (GitHub projects often use Linear):

```
mcp__plugin_linear_linear__get_issue(id: "<slug>")
```

**GitHub issues:**

```bash
gh issue view <number> --json title,body,labels,state
```

## Submit Formal Review

GitHub supports atomic review submission — all inline comments + body + review type in a single API call.

### Single API Call

```bash
REPO=$(gh repo view --json owner,name --jq '"\\(.owner.login)/\\(.name)"')

gh api "repos/${REPO}/pulls/<number>/reviews" \
  --method POST \
  --field event="<EVENT>" \
  --field body="<review_summary>" \
  --field 'comments=[
    {
      "path": "<file_path>",
      "line": <line_number>,
      "body": "<finding_body>"
    }
  ]'
```

**Event values:**
- `APPROVE` — approve the PR
- `COMMENT` — comment without approving or requesting changes
- `REQUEST_CHANGES` — request changes (blocks merge if required reviews are configured)

### Inline Comment Fields

| Field | Description |
|-------|-------------|
| `path` | File path relative to repo root |
| `line` | Line number on the **new side** of the diff |
| `body` | Comment content in Markdown |
| `start_line` | (optional) For multi-line comments, the starting line |
| `side` | (optional) `RIGHT` (default, added lines) or `LEFT` (removed lines) |

The `line` MUST be a line that appears in the diff. If the finding is about a line not in the diff, include it only in the review body.

### Important

- **ALWAYS use `gh api .../reviews`** — never use `gh pr review --comment --body` (that creates a generic timeline comment, not inline review comments)
- All inline comments are submitted atomically with the review body
- Findings without specific file:line go in the review body only

## Review Types Mapping

| Review type | GitHub event |
|-------------|-------------|
| Approve | `APPROVE` |
| Comment | `COMMENT` |
| Request Changes | `REQUEST_CHANGES` |

## Code Link Format

```
https://github.com/<owner>/<repo>/blob/<full_sha>/<path>#L<start>-L<end>
```

Detect owner/repo:

```bash
gh repo view --json owner,name --jq '"\\(.owner.login)/\\(.name)"'
```
