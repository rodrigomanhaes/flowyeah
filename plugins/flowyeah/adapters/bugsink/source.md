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

**Response:** paginated list. Take `results[0].id` as the latest event ID.

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

The core skill should use `superpowers:systematic-debugging` for the investigation phase.

## Branch Naming

Use the first 8 characters of the issue UUID as slug: `fix/<first-8-chars>`

Example: issue `68b87507-8b6f-4250-9d5c-55a1dc39d9c6` → branch `fix/68b87507`

Bugsink issues are always `fix` type — they represent errors to resolve.

## Issue Linkage

Store these values in `state.md` for use throughout the pipeline:
- **Source:** `bugsink:<issue_id>` — for state.md tracking
- **Branch type override:** always `fix`

Note: Bugsink does not support auto-close via merge keywords. No `Issue-Ref` or `Issue-Close` fields. The error resolves when the fix is deployed and no new events arrive.
