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

**Note:** Bugsink uses `Bearer` authentication:

```bash
curl -s -H "Authorization: Bearer $TOKEN"
```

## Base URL

```
<url>/api/canonical/0
```

All endpoints in the source adapter are relative to this base.

## Detecting Bugsink

Bugsink is detected from the source command prefix (`bugsink:12345`), not from the git remote.

## Write Operations Safety

The current Bugsink adapter is read-only — it fetches issue context for the build skill. If a future role adds write operations (resolving issues, posting comments, muting), follow the curl-based tactics documented in `../gitlab/connection.md` → "Write Safety":

- Save response to per-session file (`$TMPDIR_FY/...`) before parsing.
- Prefer `jq` over `python3`.
- Treat parsing failure as state-unknown; verify before retrying.

The transversal principle lives in `../_shared/write-safety.md`.
