# Bugsink Source Adapter

Fetches error details from a Bugsink instance and converts to canonical plan format for debugging.

**Connection:** See `connection.md` for authentication (uses `Bearer` auth).

## Trigger

Accepts a Bugsink URL or a prefixed issue ID:

| Input | Example |
|-------|---------|
| URL (event page) | `https://bugsink.example.com/issues/issue/68b87507-.../event/last/` |
| URL (issue page) | `https://bugsink.example.com/issues/issue/68b87507-.../` |
| Prefixed ID | `bugsink:68b87507-8b6f-4250-9d5c-55a1dc39d9c6` |

**URL detection:** Match the URL's host against `adapters.bugsink.url` in `flowyeah.yml`. Extract the issue UUID from the path segment after `/issues/issue/`.

**Plan key:** `bugsink-<first-8-chars-of-uuid>` (e.g., `bugsink-68b87507`).

## Fetch Error Details

Three API calls, chained. All endpoints are relative to `<url>/api/canonical/0`.

### Step 1: Issue metadata

```bash
TOKEN=$(grep "^<token_env>=" <token_source> | cut -d= -f2- | tr -d '"') && \
curl -s -H "Authorization: Bearer $TOKEN" \
  "<url>/api/canonical/0/issues/<issue_id>/"
```

**Response fields:**
- `calculated_type` — exception class (e.g., `ActiveRecord::StatementInvalid`)
- `calculated_value` — error message
- `transaction` — controller action or job class where the error occurred
- `digested_event_count` — total occurrences
- `first_seen` / `last_seen` — time range

### Step 2: Find the latest event

Events are at the top level, filtered by issue:

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "<url>/api/canonical/0/events/?issue=<issue_id>"
```

**Response:** paginated list sorted by newest first. Take `results[0].id` as the latest event ID — only the most recent event is needed for debugging context, so pagination beyond the first page is unnecessary.

### Step 3: Event detail with stacktrace

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "<url>/api/canonical/0/events/<event_id>/"
```

**Response fields:**
- `stacktrace_md` — pre-formatted markdown stacktrace with code context and local variables. **Use this as the primary stacktrace source.**
- `data` — full Sentry-compatible event payload with structured fields:
  - `data.request` — HTTP request details (method, URL, headers)
  - `data.tags` — environment tags (server, version, etc.)
  - `data.user` — user context
  - `data.contexts` — runtime context (OS, Ruby version, etc.)

**Alternative:** `GET /events/<event_id>/stacktrace/` returns `stacktrace_md` as plain text (useful if you only need the trace).

## Convert to Canonical Format

Bugsink errors are always prose — build a debugging-oriented plan:

```markdown
# Plan: Fix <calculated_type>: <short_message> (bugsink:<issue_id>)

## Context

- **Error:** <calculated_type>: <calculated_value>
- **Location:** <transaction> (from issue metadata)
- **Frequency:** <digested_event_count> occurrences
- **First seen:** <first_seen>
- **Request:** <method> <url> (from event data.request, if present)

## Stack Trace (abbreviated)

<top 5 application frames from stacktrace_md, skip framework/gem frames>

## Tasks
- [ ] Reproduce the error (write a failing test)
- [ ] Investigate root cause using stack trace
- [ ] Implement fix
- [ ] Verify fix resolves the original error
```

The core skill should use the debugging skill configured in `implementation.process_skills.debugging` for the investigation phase (if configured).

## Branch Naming

Use the first 8 characters of the issue UUID as slug: `fix/<first-8-chars>`

Example: issue `68b87507-8b6f-4250-9d5c-55a1dc39d9c6` → branch `fix/68b87507`

Bugsink issues are always `fix` type — they represent errors to resolve.

## Issue Linkage

Store these values in `state.md` for use throughout the pipeline:
- **Source:** `bugsink:<issue_id>` — for state.md tracking
- **Branch type override:** always `fix`

Note: Bugsink has no PR-merge auto-close keyword (no `Issue-Ref`/`Issue-Close`
fields). Instead, when `adapters.bugsink.on_merge` is configured, flowyeah
resolves the issue and posts a traceability comment via the API after merging
the fix — see "On Merge" below.

## On Merge

Runs in the build pipeline's Step 9, **only when all hold**:

- the build source was `bugsink:<id>` (`Source: bugsink:<id>` in `state.md`), and
- flowyeah performed the merge in Step 7c (`pull_requests.merge: auto`, or
  `ask` answered yes) — on `manual` or `ask`→no, skip entirely, the fix is not
  merged, and
- `adapters.bugsink.on_merge` is configured.

Read `adapters.bugsink.on_merge` from `flowyeah.yml`. Do the comment first,
then the resolve. Both are best-effort: on failure, report and continue — never
roll back the merge. Follow `connection.md` → "Write Safety" for both calls.

### Comment (`on_merge.comment`)

- `always` → build the comment body and post it.
- `never` / absent → skip.

Assemble the body from pipeline context, in the project's `language`. Omit any
line whose data is absent (e.g., no issue reference):

```
Fixed via merge.
- MR/PR: <pr_or_mr_url>
- Issue: <Issue-Ref from state.md, if present>
- Solution: <PR/MR title or short summary of the fix>
- Branch: <branch> @ <merge commit SHA>
```

Post it:

```bash
TOKEN=$(grep "^<token_env>=" <token_source> | cut -d= -f2- | tr -d '"')
TMPDIR_FY="${TMPDIR_FY:-$(mktemp -d -t flowyeah.XXXXXX)}"
jq -n --arg issue "<issue_id>" --arg comment "$COMMENT_BODY" \
  '{issue: $issue, comment: $comment}' > "$TMPDIR_FY/bugsink-comment.json"
curl -s --request POST -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  --data @"$TMPDIR_FY/bugsink-comment.json" \
  -w "\nHTTP %{http_code}\n" \
  "<url>/api/canonical/0/issue-comments/" \
  -o "$TMPDIR_FY/bugsink-comment-resp.json"
```

Confirm HTTP 201 and a numeric `.id` in the response. On an ambiguous failure,
do not retry (no dedup path) — report and point the user at the Bugsink UI.

### Resolve (`on_merge.resolve`)

- `always` → resolve.
- `ask` → prompt "Resolver bugsink:`<id>` (`<friendly_id>`)? (S/N)"; resolve on
  yes, skip on no. `<friendly_id>` comes from the issue metadata fetched in
  "Fetch Error Details".
- `never` / absent → skip.

Resolve:

```bash
curl -s --request POST -H "Authorization: Bearer $TOKEN" \
  -w "\nHTTP %{http_code}\n" \
  "<url>/api/canonical/0/issues/<issue_id>/resolve/" \
  -o "$TMPDIR_FY/bugsink-resolve-resp.json"
```

Confirm HTTP 200 and `.is_resolved == true` in the response. The call is
idempotent — safe to retry on an ambiguous failure.
