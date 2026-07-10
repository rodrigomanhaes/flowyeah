# bugsink Adapter Config Schema

Declares the keys valid under `adapters.bugsink` in flowyeah.yml.
Exhaustive — any key not listed here is unknown.

## Keys

| Key | Required | Default | Values | Notes |
|-----|----------|---------|--------|-------|
| `url` | yes | — | URL | Bugsink instance base URL |
| `token_env` | yes | — | string | Env var holding the API token |
| `token_source` | yes | — | file path | File the token is read from |
| `on_merge.resolve` | no | absent = skip | `always` \| `ask` \| `never` | Resolve the issue after merging a fix |
| `on_merge.comment` | no | absent = skip | `always` \| `never` | Post a traceability comment after merge |

## Notes

- `on_merge.resolve` uses `resolve-next/` and needs releases configured; without
  releases it degrades toward a plain resolve. Prefer `never`/`ask` if unused.
