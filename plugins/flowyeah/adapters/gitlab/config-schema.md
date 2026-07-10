# gitlab Adapter Config Schema

Declares the keys valid under `adapters.gitlab` in flowyeah.yml.
Exhaustive — any key not listed here is unknown.

## Keys

| Key | Required | Default | Values | Notes |
|-----|----------|---------|--------|-------|
| `url` | yes | — | URL | GitLab instance base URL |
| `token_env` | yes | — | string | Env var holding the API token |
| `token_source` | yes | — | file path | File the token is read from |
| `project_id` | yes | — | integer | GitLab numeric project ID |
