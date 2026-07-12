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

## Fetch Own Discussions

Fetch all discussion threads on the MR authored by the authenticated user. Used for re-review detection.

**Step 1 — Get authenticated username:**

```bash
TOKEN=$(grep "^<token_env>=" <token_source> | cut -d= -f2- | tr -d '"') && \
CURRENT_USER=$(curl -s -H "Authorization: Bearer $TOKEN" \
  "<url>/api/v4/user" | jq -r '.username')
```

**Step 2 — Fetch all discussions filtered by author:**

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "<url>/api/v4/projects/<project_id>/merge_requests/<iid>/discussions?per_page=100" | \
  jq --arg user "$CURRENT_USER" '
    [.[] | select(.notes[0].author.username == $user and .notes[0].system == false) |
     {
       discussion_id: .id,
       resolved: (.notes[0].resolvable and .notes[0].resolved),
       body: .notes[0].body,
       file: (.notes[0].position.new_path // null),
       line: (.notes[0].position.new_line // null),
       created_at: .notes[0].created_at
     }]'
```

**Pagination:** check the `x-next-page` response header. If non-empty, fetch the next page with `&page=<x-next-page>` and merge results. Continue until `x-next-page` is empty.

**Output fields:**

| Field | Description |
|-------|-------------|
| `discussion_id` | Thread ID for reference |
| `resolved` | Whether the discussion was resolved |
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

Finding bodies are multi-line markdown — raw newlines and quotes inside a hand-written JSON literal are invalid, so build the payload with `jq -n` from a file, and save the response (this write can half-succeed across N findings; see "Response handling for writes" in connection.md):

```bash
TMPDIR_FY="${TMPDIR_FY:-$(mktemp -d)}"
# write <finding_body> to "$TMPDIR_FY/finding-body.md" first (raw markdown)
jq -n --rawfile body "$TMPDIR_FY/finding-body.md" \
  --arg base "<base_sha>" --arg start "<start_sha>" --arg head "<head_sha>" \
  --arg path "<file_path>" --argjson line <line_number> '
  {body: $body, position: {base_sha: $base, start_sha: $start, head_sha: $head,
   position_type: "text", new_path: $path, new_line: $line}}' \
  > "$TMPDIR_FY/discussion-payload.json"

curl -s --request POST -H "Authorization: Bearer $TOKEN" \
  --header "Content-Type: application/json" \
  --data @"$TMPDIR_FY/discussion-payload.json" \
  -o "$TMPDIR_FY/discussion-response.json" -w "%{http_code}" \
  "<url>/api/v4/projects/<project_id>/merge_requests/<iid>/discussions"
```

Expect `201`. On any other status, keep the response file and check whether the discussion was created before retrying — when a batch fails partway, list the MR's discussions and skip findings already posted.

**Note:** Unlike most GitLab endpoints, discussions with `position` require JSON encoding, not `--form`.

**Position fields:**
- `new_path` — file path relative to repo root
- `new_line` — line number on the **new side** of the diff (added/modified lines)
- `old_path` / `old_line` — use for commenting on removed lines

The `new_line` MUST be a line that appears in the diff. If the finding is about a line not in the diff, anchor it to the nearest diff line in the same file and say in the body which line it actually concerns — never fall back to a general note; the review skill requires every finding to land as an inline discussion.

### Step 3 — Post summary note

For the overall review summary (findings always go inline — see Step 2):

```bash
TMPDIR_FY="${TMPDIR_FY:-$(mktemp -d)}"
# write <review_summary> to "$TMPDIR_FY/review-summary.md" first
SUMMARY=$(cat "$TMPDIR_FY/review-summary.md")
curl -s --request POST -H "Authorization: Bearer $TOKEN" \
  --form-string "body=$SUMMARY" \
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
