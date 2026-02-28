# New Relic Source Adapter

Fetches error details from New Relic and converts to canonical plan format for debugging.

**Connection:** See `connection.md` for NerdGraph authentication.

## Trigger

Command prefix: `NEWRELIC:<error_group_guid>`

Example: `/flowyeah from NEWRELIC:MXxBUE18...`

## Fetch Error Group Details

**NerdGraph query:**

```bash
TOKEN=$(grep "<token_env>" <token_source> | cut -d= -f2) && \
curl -s -X POST "https://api.newrelic.com/graphql" \
  -H "Content-Type: application/json" \
  -H "Api-Key: $TOKEN" \
  -d '{"query": "{ actor { errorsInbox { errorGroup(id: \"<error_group_guid>\") { name message state firstSeenAt lastSeenAt occurrences { count } assignment { email } } } } }" }'
```

**Response fields to extract:**
- `name` — error class/type
- `message` — error message
- `state` — ACTIVE, RESOLVED, IGNORED
- `firstSeenAt` / `lastSeenAt` — time range
- `occurrences.count` — how many times it occurred

## Fetch Stack Trace from Recent Error Occurrence

Query a recent error trace via NRQL:

```bash
curl -s -X POST "https://api.newrelic.com/graphql" \
  -H "Content-Type: application/json" \
  -H "Api-Key: $TOKEN" \
  -d '{"query": "{ actor { account(id: <account_id>) { nrql(query: \"SELECT * FROM TransactionError WHERE error.group.guid = '\''<error_group_guid>'\'' LIMIT 1 SINCE 7 days ago\") { results } } } }" }'
```

**Key fields from results:**
- `error.class` — exception class
- `error.message` — error message
- `error.stack_trace` — full stack trace string
- `transactionName` — controller/action or background job
- `request.uri` — URL (if web transaction)
- `host` — server hostname
- `appName` — application name

If `error.stack_trace` is absent, try fetching from the error trace entity:

```bash
curl -s -X POST "https://api.newrelic.com/graphql" \
  -H "Content-Type: application/json" \
  -H "Api-Key: $TOKEN" \
  -d '{"query": "{ actor { account(id: <account_id>) { nrql(query: \"SELECT stackTrace, error.class, error.message, transactionName FROM TransactionError WHERE error.group.guid = '\''<error_group_guid>'\'' LIMIT 1 SINCE 7 days ago\") { results } } } }" }'
```

## Convert to Canonical Format

New Relic errors are always prose — build a debugging-oriented plan:

```markdown
# Plan: Fix <error_class>: <error_message> (NEWRELIC:<error_group_guid>)

## Context

- **Error:** <error_class>: <error_message>
- **Transaction:** <transactionName>
- **Occurrences:** <count> since <firstSeenAt>
- **Last seen:** <lastSeenAt>
- **App:** <appName>

## Stack Trace (abbreviated)

<top application frames, skip framework frames>

## Tasks
- [ ] Reproduce the error (write a failing test)
- [ ] Investigate root cause using stack trace
- [ ] Implement fix
- [ ] Verify fix resolves the original error
```

The core skill should use `superpowers:systematic-debugging` for the investigation phase.

## Branch Naming

Use a short slug derived from the error class: `fix/<error-class-slug>`

Example: `NoMethodError` → `fix/no-method-error`

The full error group GUID is too long for branch names — record it in `state.md` for reference.

## Issue Linkage

Pass these values:
- **Source reference:** `NEWRELIC:<error_group_guid>` (for state.md tracking)
- **Branch type override:** always `fix`

Note: New Relic error groups auto-resolve when no new occurrences arrive after deployment. No API call needed to close them.
