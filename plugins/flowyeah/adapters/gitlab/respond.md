# GitLab Respond Adapter

Fetches unresolved discussion threads, replies to comments, resolves discussions, and re-requests review via the GitLab API.

**Connection:** See `connection.md` for authentication and API conventions.

## Fetch Unresolved Discussions

Get all unresolved, resolvable discussion threads on the MR. Captures the first note in each thread (the review finding).

```bash
TOKEN=$(grep "^<token_env>=" <token_source> | cut -d= -f2- | tr -d '"') && \
curl -s -H "Authorization: Bearer $TOKEN" \
  "<url>/api/v4/projects/<project_id>/merge_requests/<iid>/discussions?per_page=100" | \
  jq '[.[] | select(.notes[0].resolvable == true and .notes[0].resolved == false) |
   {
     discussion_id: .id,
     author: .notes[0].author.username,
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
| `discussion_id` | Thread ID (used for replying and resolving) |
| `author` | Reviewer username who authored the finding |
| `body` | Comment body (may use Conventional Comments format) |
| `file` | File path (null for general comments) |
| `line` | Line number on the new side (null for general comments) |
| `created_at` | Timestamp for ordering |

**Parsing Conventional Comments:** Extract structured data from the body:

```
Pattern: **<label> (<decoration>):** <subject>\n\n<discussion>
Example: **issue (blocking):** Race condition na criação de pagamento
```

If the body does not match Conventional Comments format, treat it as a free-form comment.

## Fetch Review/Approval State

GitLab does not have a `CHANGES_REQUESTED` review state like GitHub. Instead, unresolved resolvable threads serve as a proxy: a reviewer who has unresolved threads is effectively requesting changes.

**Count unresolved threads per author:**

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "<url>/api/v4/projects/<project_id>/merge_requests/<iid>/discussions?per_page=100" | \
  jq '[.[] | select(.notes[0].resolvable == true and .notes[0].resolved == false) |
   .notes[0].author.username] | group_by(.) | map({user: .[0], unresolved_count: length})'
```

**Pagination:** same `x-next-page` pattern as above — paginate and merge before grouping.

**Interpreting the result:** If a reviewer has `unresolved_count > 0`, they are effectively requesting changes. Once the respond process resolves all their threads, re-request review from them (see below).

**Approval status:**

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "<url>/api/v4/projects/<project_id>/merge_requests/<iid>/approvals" | \
  jq '{approved_by: [.approved_by[].user.username], approvals_left: .approvals_left}'
```

## Reply to Discussion

Post a note to an existing discussion thread. The reply appears nested under the original comment, keeping the conversation in context.

```bash
curl -s --request POST -H "Authorization: Bearer $TOKEN" \
  --form "body=<reply_text>" \
  "<url>/api/v4/projects/<project_id>/merge_requests/<iid>/discussions/<discussion_id>/notes"
```

## Resolve Discussion

Mark a discussion as resolved. Call this after addressing the feedback and posting a reply.

```bash
curl -s --request PUT -H "Authorization: Bearer $TOKEN" \
  --form "resolved=true" \
  "<url>/api/v4/projects/<project_id>/merge_requests/<iid>/discussions/<discussion_id>"
```

**Note:** Resolving a discussion sets all notes in that thread as resolved. There is no way to resolve individual notes within a discussion.

## Re-request Review

GitLab does not have a dedicated "re-request review" action. The closest equivalent is removing and re-adding the reviewer, which triggers a notification.

**Step 1 — Get current reviewer IDs:**

```bash
REVIEWER_IDS=$(curl -s -H "Authorization: Bearer $TOKEN" \
  "<url>/api/v4/projects/<project_id>/merge_requests/<iid>" | \
  jq '[.reviewers[].id]')
```

**Step 2 — Update reviewers (PUT replaces the full list):**

```bash
curl -s --request PUT -H "Authorization: Bearer $TOKEN" \
  --header "Content-Type: application/json" \
  --data "{\"reviewer_ids\": $REVIEWER_IDS}" \
  "<url>/api/v4/projects/<project_id>/merge_requests/<iid>"
```

**Note:** The PUT with `reviewer_ids` requires JSON encoding (not `--form`) because the value is an array. This is an exception to the general GitLab `--form` convention — see `connection.md`.

**When to re-request:** Only re-request review from reviewers whose unresolved threads were all resolved during the respond process. Re-requesting from reviewers who still have unresolved threads is counterproductive.
