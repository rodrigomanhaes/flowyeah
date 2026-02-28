# GitLab Review Adapter

Fetches merge request details and submits formal code reviews with inline comments via the GitLab API.

**Connection:** See `connection.md` for authentication and API conventions.

## Identify the MR

**From a PR number:**

```bash
TOKEN=$(grep "^<token_env>=" <token_source> | cut -d= -f2- | tr -d '"') && \
curl -s -H "Authorization: Bearer $TOKEN" \
  "<url>/api/v4/projects/<project_id>/merge_requests/<iid>" | \
  jq '{iid, title, state, source_branch, target_branch, web_url, author: .author.username, diff_refs}'
```

**From the current branch:**

```bash
BRANCH=$(git branch --show-current)
TOKEN=$(grep "^<token_env>=" <token_source> | cut -d= -f2- | tr -d '"') && \
curl -s -H "Authorization: Bearer $TOKEN" \
  "<url>/api/v4/projects/<project_id>/merge_requests?source_branch=$BRANCH&state=opened" | \
  jq '.[0] | {iid, title, state, source_branch, target_branch, web_url, author: .author.username, diff_refs}'
```

## Fetch Diff

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "<url>/api/v4/projects/<project_id>/merge_requests/<iid>/diffs" | \
  jq '.[] | {old_path, new_path, diff}'
```

For changed files list:

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "<url>/api/v4/projects/<project_id>/merge_requests/<iid>/changes" | \
  jq '.changes[] | {old_path, new_path, new_file, deleted_file}'
```

## Fetch Commits

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "<url>/api/v4/projects/<project_id>/merge_requests/<iid>/commits" | \
  jq '.[] | {id, title, message}'
```

## Detect Associated Issue

**Extract issue slug from branch name:**

| Pattern | Examples |
|---------|----------|
| Leading digits | `42-add-pix`, `5588-fix-export` |
| `feat/<digits>`, `fix/<digits>` | `feat/42`, `fix/5588` |
| `(proj\|projx\|team\|web)(-[a-z]+)?-\d+` (case-insensitive) | `PROJ-123`, `proj-eng-302`, `TEAM-456` |

**GitLab issues:**

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "<url>/api/v4/projects/<project_id>/issues/<iid>"
```

**Linear issues** (GitLab projects may use Linear for issue tracking):

```
mcp__plugin_linear_linear__get_issue(id: "<slug>")
```

Extract: title, description, labels, comments (for requirements validation).

## Submit Formal Review

GitLab uses **discussions** for inline review comments. Each discussion creates a resolvable thread anchored to a specific line in the diff.

### Step 1 — Get diff_refs

```bash
DIFF_REFS=$(curl -s -H "Authorization: Bearer $TOKEN" \
  "<url>/api/v4/projects/<project_id>/merge_requests/<iid>" | \
  jq '.diff_refs')
```

Extract `base_sha`, `start_sha`, and `head_sha` from the response.

### Step 2 — Post inline comments as discussions

For each finding with a specific file and line:

```bash
curl -s --request POST -H "Authorization: Bearer $TOKEN" \
  --header "Content-Type: application/json" \
  --data '{
    "body": "<finding_body>",
    "position": {
      "base_sha": "<base_sha>",
      "start_sha": "<start_sha>",
      "head_sha": "<head_sha>",
      "position_type": "text",
      "new_path": "<file_path>",
      "new_line": <line_number>
    }
  }' \
  "<url>/api/v4/projects/<project_id>/merge_requests/<iid>/discussions"
```

**Note:** Unlike most GitLab endpoints, discussions with `position` require JSON encoding, not `--form`.

**Position fields:**
- `new_path` — file path relative to repo root
- `new_line` — line number on the **new side** of the diff (added/modified lines)
- `old_path` / `old_line` — use for commenting on removed lines

The `new_line` MUST be a line that appears in the diff. If the finding is about a line not in the diff, use the nearest diff line in the same file, or post as a general note instead.

### Step 3 — Post summary note

For the overall review summary (and findings without specific file:line):

```bash
curl -s --request POST -H "Authorization: Bearer $TOKEN" \
  --form "body=<review_summary>" \
  "<url>/api/v4/projects/<project_id>/merge_requests/<iid>/notes"
```

### Step 4 — Approve or unapprove

**Approve:**
```bash
curl -s --request POST -H "Authorization: Bearer $TOKEN" \
  "<url>/api/v4/projects/<project_id>/merge_requests/<iid>/approve"
```

**Unapprove (revoke approval):**
```bash
curl -s --request POST -H "Authorization: Bearer $TOKEN" \
  "<url>/api/v4/projects/<project_id>/merge_requests/<iid>/unapprove"
```

GitLab does not have a "Request Changes" state like GitHub. Instead:
- **Approve** → approve the MR
- **Comment** → post inline discussions + summary note (default)
- **Request Changes** → post inline discussions + summary note + do NOT approve

## Review Types Mapping

| Review type | GitLab action |
|-------------|---------------|
| Approve | Inline discussions + summary note + `/approve` |
| Comment | Inline discussions + summary note |
| Request Changes | Inline discussions + summary note (no approve) |

## Code Link Format

```
<url>/<namespace>/<project>/-/blob/<full_sha>/<path>#L<start>-L<end>
```
