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
| `(proj\|projx\|team\|web)(-[a-z]+)?-\d+` (case-insensitive) | `PROJ-123`, `proj-eng-302`, `TEAM-456` |
| Leading digits or `feat/\d+`, `fix/\d+` | `feat/42`, `42-add-pix` |

**Linear issues** (GitHub projects often use Linear):

```
mcp__plugin_linear_linear__get_issue(id: "<slug>")
```

**GitHub issues:**

```bash
gh issue view <number> --json title,body,labels,state
```

## Fetch Own Discussions

Fetch all review comments on the PR authored by the authenticated user. Used for re-review detection.

**Step 1 — Get authenticated username:**

```bash
CURRENT_USER=$(gh api user --jq '.login')
```

**Step 2 — Fetch review threads with resolution status via GraphQL:**

```bash
REPO_OWNER=$(gh repo view --json owner --jq '.owner.login')
REPO_NAME=$(gh repo view --json name --jq '.name')

gh api graphql -f query='
  query($owner: String!, $repo: String!, $number: Int!, $cursor: String) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $number) {
        reviewThreads(first: 100, after: $cursor) {
          pageInfo {
            hasNextPage
            endCursor
          }
          nodes {
            isResolved
            comments(first: 1) {
              nodes {
                databaseId
                author { login }
                body
                path
                line
                createdAt
              }
            }
          }
        }
      }
    }
  }' -f owner="$REPO_OWNER" -f repo="$REPO_NAME" -F number=<number> | \
  jq --arg user "$CURRENT_USER" '
  [.data.repository.pullRequest.reviewThreads.nodes[] |
   select(.comments.nodes[0].author.login == $user) |
   {
     comment_id: .comments.nodes[0].databaseId,
     resolved: .isResolved,
     body: .comments.nodes[0].body,
     file: .comments.nodes[0].path,
     line: .comments.nodes[0].line,
     created_at: .comments.nodes[0].createdAt
   }]'
```

**Pagination:** if `pageInfo.hasNextPage` is `true`, repeat the query with `-f cursor=<endCursor>` and merge results. Continue until `hasNextPage` is `false`.

**Output fields:**

| Field | Description |
|-------|-------------|
| `comment_id` | Comment database ID for reference |
| `resolved` | Whether the review thread was resolved |
| `body` | Comment body (Conventional Comments format) |
| `file` | File path (null for general comments) |
| `line` | Line number (null for general comments) |
| `created_at` | Timestamp for ordering |

**Parsing Conventional Comments:** Extract structured data from the body:

```
Pattern: **<label> (<decoration>):** <subject>\n\n<discussion>
Example: **issue (blocking):** Race condition na criação de pagamento
```

If the body does not match Conventional Comments format, skip it (likely a manual comment, not a structured review finding).

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
- `APPROVE` — approve the PR. **Do NOT include inline `comments`** — they create open review threads that block auto-merge in repos requiring conversation resolution. Move all findings to the review `body` instead.
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

### Large Payloads

When the `comments` array is large (many findings), `--field` may hit shell argument limits. Use `--input -` with a JSON payload instead:

```bash
REPO=$(gh repo view --json owner,name --jq '"\\(.owner.login)/\\(.name)"')

cat <<'JSON' | gh api "repos/${REPO}/pulls/<number>/reviews" --method POST --input -
{
  "event": "<EVENT>",
  "body": "<review_summary>",
  "comments": [
    {"path": "<file>", "line": <n>, "body": "<finding>"},
    {"path": "<file>", "line": <n>, "body": "<finding>"}
  ]
}
JSON
```

### Important

- **ALWAYS use `gh api .../reviews`** — never use `gh pr review --comment --body` (that creates a generic timeline comment, not inline review comments)
- All inline comments are submitted atomically with the review body
- For many findings, prefer `--input -` over `--field` to avoid shell limits
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
