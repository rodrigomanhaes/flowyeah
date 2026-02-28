# Bugsink Connection

Shared authentication and API conventions for all Bugsink adapters.

## Required Config (`flowyeah.yml`)

```yaml
adapters:
  bugsink:
    url: https://bugsink.example.com
    token_env: BUGSINK_TOKEN
    token_source: .env
```

## Authentication

Extract the token directly from the configured file:

```bash
TOKEN=$(grep "^<token_env>=" <token_source> | cut -d= -f2- | tr -d '"')
```

**Note:** Bugsink uses `Token` authentication (not `Bearer`):

```bash
curl -s -H "Authorization: Token $TOKEN"
```

## Base URL

```
<url>/api
```

All endpoints in the source adapter are relative to this base.

## Detecting Bugsink

Bugsink is detected from the source command prefix (`BUGSINK:12345`), not from the git remote.
