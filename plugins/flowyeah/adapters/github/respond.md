# GitHub Respond Adapter

Fetches unresolved review threads and remarks outside threads, replies to comments, resolves conversations, acknowledges remarks with a reaction, and re-requests review via the GitHub API.

**Connection:** See `connection.md` for authentication.

## Fetch Unresolved Review Threads

GraphQL query to get all unresolved review threads across all reviewers. Captures the first comment in each thread (the review finding).

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
            id
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
  jq '[.data.repository.pullRequest.reviewThreads.nodes[] |
   select(.isResolved == false) |
   {
     thread_id: .id,
     comment_id: .comments.nodes[0].databaseId,
     author: .comments.nodes[0].author.login,
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
| `thread_id` | Thread node ID (used for resolving the thread) |
| `comment_id` | Comment database ID (used for replying in-thread) |
| `author` | Reviewer login who authored the comment |
| `body` | Comment body (may use Conventional Comments format) |
| `file` | File path (null for general comments) |
| `line` | Line number (null for general comments) |
| `created_at` | Timestamp for ordering |

**Parsing Conventional Comments:** Extract structured data from the body:

```
Pattern: **<label> (<decoration>):** <subject>\n\n<discussion>
Example: **issue (blocking):** Race condition na criação de pagamento
```

If the body does not match Conventional Comments format, treat it as a free-form comment.

## Fetch Remarks Outside Threads

A reviewer can ask for something without opening a thread: in the body of a review, or in a comment on the pull request's conversation. These remarks have no thread to reply to or resolve. Fetch the ones that arrived after your last remark outside a thread and that you have not reacted to.

```bash
REPO_OWNER=$(gh repo view --json owner --jq '.owner.login')
REPO_NAME=$(gh repo view --json name --jq '.name')
ME=$(gh api user --jq .login)

{
gh api graphql --paginate -f query='
  query($owner: String!, $repo: String!, $number: Int!, $endCursor: String) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $number) {
        comments(first: 100, after: $endCursor) {
          pageInfo { hasNextPage endCursor }
          nodes { id author { login } body createdAt url reactionGroups { viewerHasReacted } }
        }
      }
    }
  }' -f owner="$REPO_OWNER" -f repo="$REPO_NAME" -F number=<number> \
  --jq '.data.repository.pullRequest.comments.nodes[] |
    {subject_id: .id, kind: "comment", state: null, author: .author.login, body,
     created_at: .createdAt, url, seen: ([.reactionGroups[]?.viewerHasReacted] | any)}'
gh api graphql --paginate -f query='
  query($owner: String!, $repo: String!, $number: Int!, $endCursor: String) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $number) {
        reviews(first: 100, after: $endCursor) {
          pageInfo { hasNextPage endCursor }
          nodes { id author { login } body state submittedAt url reactionGroups { viewerHasReacted } }
        }
      }
    }
  }' -f owner="$REPO_OWNER" -f repo="$REPO_NAME" -F number=<number> \
  --jq '.data.repository.pullRequest.reviews.nodes[] | select(.submittedAt != null) |
    {subject_id: .id, kind: "review", state, author: .author.login, body,
     created_at: .submittedAt, url, seen: ([.reactionGroups[]?.viewerHasReacted] | any)}'
} | jq -s --arg me "$ME" '
  (map(select(.author == $me) | .created_at) | max) as $last
  | map(select(.author != $me
      and (.kind == "comment" or .state == "COMMENTED" or .state == "CHANGES_REQUESTED")
      and (.body | gsub("\\s"; "") != "")
      and ($last == null or .created_at > $last)
      and (.seen | not)))'
```

`--paginate` on a GraphQL query walks the one connection that takes `$endCursor`, which is why comments and reviews are two queries.

What the filter keeps, and why:

- **Every author but you, bots included.** A review bot often writes its findings in the review body. A bot that posts a notice on every push edits the same comment, so once you react to it, it stays acknowledged.
- **Comments, and reviews that comment or request changes.** An approval asks for nothing.
- **A non-empty body.** Every reply in a thread is filed as a review with an empty body; its content lives in the thread.
- **After your last remark outside a thread.** Your own reviews count, thread replies included, because each one is filed as a review. Everything before it you already answered.
- **Not reacted to by you.** A reaction is how a remark outside a thread is acknowledged (see "Acknowledge a Remark").

**Output fields:**

| Field | Description |
|-------|-------------|
| `subject_id` | Node ID of the comment or review (used for the reaction) |
| `kind` | `comment` or `review` |
| `state` | Review state, `null` for a comment |
| `author` | Login of who wrote it |
| `body` | Text (may use Conventional Comments format) |
| `created_at` | When it was posted or submitted |
| `url` | Link to it, for the reply that quotes it |

## Fetch Review States

Get each reviewer's most recent review state. Used to determine re-request eligibility.

The endpoint returns 30 reviews per page and `.[-1]` must see the whole history — paginate, then group across all pages (with `--paginate`, gh applies `--jq` per page, so the grouping runs in a second jq over the merged stream):

```bash
REPO=$(gh repo view --json owner,name --jq '"\(.owner.login)/\(.name)"')

gh api --paginate "repos/${REPO}/pulls/<number>/reviews" --jq '.[]' | jq -s '
  [group_by(.user.login)[] | {
    user: .[0].user.login,
    state: .[-1].state
  }]'
```

**State values:**

| State | Description |
|-------|-------------|
| `APPROVED` | Reviewer approved the PR |
| `CHANGES_REQUESTED` | Reviewer requested changes (eligible for re-request) |
| `COMMENTED` | Reviewer left comments without formal approval/rejection |
| `DISMISSED` | Review was dismissed |

## Reply to Thread

Post an in-thread reply using the comment database ID from the unresolved threads query.

```bash
REPO=$(gh repo view --json owner,name --jq '"\(.owner.login)/\(.name)"')

gh api "repos/${REPO}/pulls/<number>/comments/<comment_id>/replies" \
  --method POST --field body="<reply_text>"
```

The reply appears nested under the original review comment, keeping the conversation in context.

## Resolve Thread

GraphQL mutation using the thread node ID from the unresolved threads query. Call this after addressing the feedback and posting a reply.

```bash
gh api graphql -f query='
  mutation($threadId: ID!) {
    resolveReviewThread(input: {threadId: $threadId}) {
      thread { isResolved }
    }
  }' -f threadId="<thread_node_id>"
```

## Reply to a Remark Outside a Thread

A remark outside a thread has no thread to reply in, so the answer is a new comment on the pull request. Mention the author and link the remark, so the answer stays attached to what it answers.

```bash
REPO=$(gh repo view --json owner,name --jq '"\(.owner.login)/\(.name)"')

gh api "repos/${REPO}/issues/<number>/comments" \
  --method POST --raw-field body="@<author> <reply_text>

> <first line of the remark> ([original](<url>))"
```

`--raw-field` because the body starts with `@`, which `--field` reads as a file path.

## Acknowledge a Remark

A remark outside a thread cannot be resolved. A reaction tells its author you read it and owe nothing back, and the fetch above skips a remark you reacted to.

```bash
gh api graphql -f query='
  mutation($subjectId: ID!) {
    addReaction(input: {subjectId: $subjectId, content: THUMBS_UP}) {
      reaction { content }
    }
  }' -f subjectId="<subject_id>"
```

The same mutation serves a comment and a review: both are `Reactable`.

## Re-request Review

Re-request behavior depends on whether code was pushed in this respond cycle.

### When code was changed (push happened)

New commits dismiss existing approvals (standard branch protection). Re-request from **all** reviewers except `DISMISSED`, and notify previously-approved reviewers via a PR comment.

| State | Re-request? | Reason |
|-------|-------------|--------|
| `CHANGES_REQUESTED` | Yes | Reviewer blocked the PR and needs to re-evaluate |
| `COMMENTED` | Yes | Reviewer left feedback and should see the response |
| `APPROVED` | Yes | Approval was dismissed by the new push — needs re-approval |
| `DISMISSED` | No | Review was dismissed before this cycle |

**Post a PR comment** mentioning previously-approved reviewers so they're notified their approval was dismissed:

```bash
REPO=$(gh repo view --json owner,name --jq '"\(.owner.login)/\(.name)"')

gh api "repos/${REPO}/issues/<number>/comments" \
  --method POST --field body="@reviewer1 @reviewer2 — <notification text>"
```

### When no code was changed (replies only)

Approvals remain intact. Only re-request from reviewers with pending feedback.

| State | Re-request? | Reason |
|-------|-------------|--------|
| `CHANGES_REQUESTED` | Yes | Reviewer blocked the PR and needs to re-evaluate |
| `COMMENTED` | Yes | Reviewer left feedback and should see the response |
| `APPROVED` | No | Approval still valid — no code changed |
| `DISMISSED` | No | Review was dismissed |

### API calls

Re-requesting review does not block CI or merge — it sends a notification and marks the reviewer as pending, but does not prevent other approvers from merging.

**Single reviewer:**

```bash
REPO=$(gh repo view --json owner,name --jq '"\(.owner.login)/\(.name)"')

gh api "repos/${REPO}/pulls/<number>/requested_reviewers" \
  --method POST --field 'reviewers[]=<username>'
```

**Multiple reviewers:**

```bash
REPO=$(gh repo view --json owner,name --jq '"\(.owner.login)/\(.name)"')

gh api "repos/${REPO}/pulls/<number>/requested_reviewers" \
  --method POST --field 'reviewers[]=user1' --field 'reviewers[]=user2'
```
