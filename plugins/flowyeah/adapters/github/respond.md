# GitHub Respond Adapter

Fetches unresolved review threads, replies to comments, resolves conversations, and re-requests review via the GitHub API.

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

## Fetch Review States

Get each reviewer's most recent review state. Used to determine re-request eligibility.

```bash
REPO=$(gh repo view --json owner,name --jq '"\(.owner.login)/\(.name)"')

gh api "repos/${REPO}/pulls/<number>/reviews" --jq '
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
      reviewThread { isResolved }
    }
  }' -f threadId="<thread_node_id>"
```

## Re-request Review

Only call this for reviewers whose most recent state is `CHANGES_REQUESTED` (see Fetch Review States above).

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

Re-requesting review from a reviewer whose state is `APPROVED` or `COMMENTED` is harmless but unnecessary — only `CHANGES_REQUESTED` blocks merge in protected branches.
