# Bugsink Source Adapter

Fetches error details from a Bugsink instance and converts to canonical plan format for debugging.

**Connection:** See `connection.md` for authentication (uses `Token` auth, not `Bearer`).

## Trigger

Command prefix: `BUGSINK:<issue_id>`

Example: `/flowyeah from BUGSINK:45678`

## Fetch Error Details

**Endpoint:** `GET /api/issues/<issue_id>/`

```bash
TOKEN=$(grep "<token_env>" <token_source> | cut -d= -f2) && \
curl -s -H "Authorization: Token $TOKEN" \
  "<url>/api/issues/<issue_id>/"
```

**Response fields to extract:**
- `title` — error summary (exception class + message)
- `last_event.data` — full Sentry-compatible event payload

**Get the latest event for detailed traceback:**

```bash
curl -s -H "Authorization: Token $TOKEN" \
  "<url>/api/issues/<issue_id>/events/latest/"
```

**Key fields from event data:**
- `exception.values[].type` — exception class
- `exception.values[].value` — error message
- `exception.values[].stacktrace.frames[]` — stack frames with `filename`, `lineno`, `function`, `context_line`
- `tags` — environment tags (server, version, etc.)
- `request` — HTTP request details (if web error)

## Convert to Canonical Format

Bugsink errors are always prose — build a debugging-oriented plan:

```markdown
# Plan: Fix <exception_type>: <error_message> (BUGSINK:<issue_id>)

## Context

- **Error:** <exception_type>: <error_message>
- **Location:** <filename>:<lineno> in <function>
- **Frequency:** <event_count> occurrences
- **Environment:** <tags summary>

## Stack Trace (abbreviated)

<top 5 application frames, skip framework frames>

## Tasks
- [ ] Reproduce the error (write a failing test)
- [ ] Investigate root cause using stack trace
- [ ] Implement fix
- [ ] Verify fix resolves the original error
```

The core skill should use `superpowers:systematic-debugging` for the investigation phase.

## Branch Naming

Use the issue ID as slug: `fix/<issue_id>`

Bugsink issues are always `fix` type — they represent errors to resolve.

## Issue Linkage

Pass these values:
- **Source reference:** `BUGSINK:<issue_id>` (for state.md tracking)
- **Branch type override:** always `fix`

Note: Bugsink does not support auto-close via merge keywords. The error resolves when the fix is deployed and no new events arrive.
