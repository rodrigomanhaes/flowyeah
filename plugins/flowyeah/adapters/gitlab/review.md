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

**Pagination:** the `curl -s | jq` templates discard response headers, so paginate by page number: request `&page=2`, `&page=3`, ... merging results, until a page returns fewer than `per_page` items (or an empty array).

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

## Search Recent Merged MR Feedback

Find review comments from recently merged MRs that touched the same files. GitLab's MR list cannot filter by file, so bound the work: list the 20 most recent merged MRs, check the diffs of the few whose titles look related, and stop there — degrade gracefully rather than fetching every MR's diff:

```bash
# Recent merged MRs
curl -s -H "Authorization: Bearer $TOKEN" \
  "<url>/api/v4/projects/<project_id>/merge_requests?state=merged&order_by=updated_at&per_page=20" | \
  jq '[.[] | {iid, title}]'

# Files touched by one of them
curl -s -H "Authorization: Bearer $TOKEN" \
  "<url>/api/v4/projects/<project_id>/merge_requests/<iid>/diffs?per_page=100" | \
  jq '[.[].new_path]'

# Its review discussions (first page is enough for theme detection)
curl -s -H "Authorization: Bearer $TOKEN" \
  "<url>/api/v4/projects/<project_id>/merge_requests/<iid>/discussions?per_page=100" | \
  jq '[.[].notes[] | select(.system == false) | {author: .author.username, body: .body}]'
```

## Submit Formal Review

GitLab uses **discussions** for inline review comments. Each discussion creates a resolvable thread anchored to a specific line in the diff. Discussions and notes do not count as a review: the reviewer's state stays `unreviewed` until Step 5 declares it.

### Step 1 — Check for pending draft notes

Step 5 publishes **every** pending draft note the user has on the MR, including ones written by hand in the GitLab UI and never submitted. Check before posting anything:

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "<url>/api/v4/projects/<project_id>/merge_requests/<iid>/draft_notes" | \
  jq '[.[] | {id, note: .note[0:80], file: (.position.new_path // null)}]'
```

If the list is not empty, STOP and show the drafts to the user before submitting: Step 5 would publish them along with the review.

### Step 2 — Get diff_refs

```bash
DIFF_REFS=$(curl -s -H "Authorization: Bearer $TOKEN" \
  "<url>/api/v4/projects/<project_id>/merge_requests/<iid>" | \
  jq '.diff_refs')
```

Extract `base_sha`, `start_sha`, and `head_sha` from the response.

### Step 3 — Post inline comments as discussions

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

### Step 4 — Post summary note

For the overall review summary (findings always go inline — see Step 3):

```bash
TMPDIR_FY="${TMPDIR_FY:-$(mktemp -d)}"
# write <review_summary> to "$TMPDIR_FY/review-summary.md" first
SUMMARY=$(cat "$TMPDIR_FY/review-summary.md")
curl -s --request POST -H "Authorization: Bearer $TOKEN" \
  --form-string "body=$SUMMARY" \
  "<url>/api/v4/projects/<project_id>/merge_requests/<iid>/notes"
```

### Step 5 — Declare the review state

Without this call GitLab keeps the reviewer as `unreviewed`, and the MR stays in the reviewer's queue no matter how many discussions were posted. `reviewer_state` takes `requested_changes` or `reviewed` (see Review Types Mapping); the call needs no pending drafts and responds `204`:

```bash
curl -s --request POST -H "Authorization: Bearer $TOKEN" \
  --form-string "reviewer_state=<requested_changes|reviewed>" \
  -w "%{http_code}" \
  "<url>/api/v4/projects/<project_id>/merge_requests/<iid>/draft_notes/bulk_publish"
```

Confirm the state landed:

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "<url>/api/v4/projects/<project_id>/merge_requests/<iid>/reviewers" | \
  jq --arg user "$CURRENT_USER" '.[] | select(.user.username == $user) | .state'
```

`$CURRENT_USER` comes from Fetch Own Discussions, Step 1. Expect the state just sent. If the user is not in the reviewers list or the state is still `unreviewed`, report it to the user — the review was posted but GitLab does not record it as one.

### Step 6 — Approve or unapprove

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

## Review Types Mapping

| Review type | GitLab action |
|-------------|---------------|
| Approve | Inline discussions + summary note + `reviewer_state=reviewed` + `/approve` |
| Comment | Inline discussions + summary note + `reviewer_state=reviewed` |
| Request Changes | Inline discussions + summary note + `reviewer_state=requested_changes` (no approve) |

## Code Link Format

```
<url>/<namespace>/<project>/-/blob/<full_sha>/<path>#L<start>-L<end>
```
