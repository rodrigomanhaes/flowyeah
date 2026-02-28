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

New Relic is detected from the source command prefix (`NEWRELIC:MXxBUE18...`), not from the git remote.
