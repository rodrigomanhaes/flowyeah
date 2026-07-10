# newrelic Adapter Config Schema

Declares the keys valid under `adapters.newrelic` in flowyeah.yml.
Exhaustive — any key not listed here is unknown.

## Keys

| Key | Required | Default | Values | Notes |
|-----|----------|---------|--------|-------|
| `account_id` | yes | — | integer | New Relic account ID |
| `token_env` | yes | — | string | Env var holding the API key |
| `token_source` | yes | — | file path | File the key is read from |
