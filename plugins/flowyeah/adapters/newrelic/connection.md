# New Relic Connection

Shared authentication and API conventions for all New Relic adapters.

## Required Config (`flowyeah.yml`)

```yaml
adapters:
  newrelic:
    account_id: 1234567
    token_env: NEW_RELIC_API_KEY
    token_source: .env
```

## Authentication

Extract the token directly from the configured file:

```bash
TOKEN=$(grep "^<token_env>=" <token_source> | cut -d= -f2- | tr -d '"')
```

All API calls use New Relic's NerdGraph (GraphQL) endpoint:

```
https://api.newrelic.com/graphql
```

Header: `Api-Key: $TOKEN`

```bash
curl -s -X POST "https://api.newrelic.com/graphql" \
  -H "Content-Type: application/json" \
  -H "Api-Key: $TOKEN" \
  -d '{"query": "..."}'
```

## Detecting New Relic

New Relic is detected from the source command prefix (`newrelic:MXxBUE18...`), not from the git remote.

## Write Operations Safety

NerdGraph (the GraphQL endpoint above) supports both queries and mutations on the same URL. Current adapter usage is read-only (`query { ... }`). If a future role issues mutations (`mutation { ... }` — creating workloads, dashboards, alert policies, etc.), follow the rules below.

**See also: `../_shared/write-safety.md`** for the transversal principle (parsing failure ≠ operation failure; verify before retry).

### GraphQL-specific: check both `data` and `errors`

GraphQL responses can contain **both** a successful `data` field and an `errors` array — partial success is possible. Always inspect `errors` before assuming the mutation landed cleanly:

```bash
TMPDIR_FY="${TMPDIR_FY:-$(mktemp -d -t flowyeah.XXXXXX)}"
curl -s -X POST "https://api.newrelic.com/graphql" \
  -H "Content-Type: application/json" \
  -H "Api-Key: $TOKEN" \
  -d @"$TMPDIR_FY/mutation.json" \
  -w "\nHTTP %{http_code}\n" \
  -o "$TMPDIR_FY/resp.json"

# Check for partial failures
jq '.errors // empty' "$TMPDIR_FY/resp.json"
jq '.data' "$TMPDIR_FY/resp.json"
```

A 200 OK with `errors` populated means the request was processed but at least one resolver failed — treat as state-uncertain, not state-known.

### Other tactics

Same as gitlab/curl-based adapters:

- Save response to per-session tempfile, never pipe `curl` straight to a parser.
- Prefer `jq` over `python3` (GraphQL responses can carry escaped control chars in error messages).
- Use per-session paths (`$TMPDIR_FY` or `$(mktemp -d)`), not hardcoded `/tmp/...`.
- After a timeout or parse failure on a mutation, verify state via a follow-up query before retrying.
