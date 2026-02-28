# GitLab Connection

Shared authentication and API conventions for all GitLab adapters.

## Required Config (`flowyeah.yml`)

GitLab config appears in both `sink` and `sources.gitlab`. Use whichever is available:

```yaml
# As sink
sink:
  adapter: gitlab
  url: https://gitlab.example.com
  token_env: GITLAB_TOKEN
  token_source: .env
  project_id: 123

# As source
sources:
  gitlab:
    url: https://gitlab.example.com
    token_env: GITLAB_TOKEN
    token_source: .env
    project_id: 123
```

## Authentication

Extract the token directly from the configured file. **Do NOT `source` the file** — it may not work correctly in subshells:

```bash
TOKEN=$(grep "<token_env>" <token_source> | cut -d= -f2)
```

All API calls use:

```bash
curl -s -H "Authorization: Bearer $TOKEN"
```

## Base URL

```
<url>/api/v4/projects/<project_id>
```

All endpoints in source, sink, and review adapters are relative to this base.

## Encoding

**Use `--form` encoding for write operations** (POST, PUT). GitLab may return 401 with JSON `Content-Type`:

```bash
# Correct
curl -s --request POST -H "Authorization: Bearer $TOKEN" \
  --form "title=My Title" \
  "<url>/api/v4/projects/<project_id>/endpoint"

# Incorrect (may return 401)
curl -s --request POST -H "Authorization: Bearer $TOKEN" \
  --header "Content-Type: application/json" \
  --data '{"title": "My Title"}' \
  "<url>/api/v4/projects/<project_id>/endpoint"
```

Read operations (GET) don't need `--form`.

## Detecting GitLab

When auto-detecting the platform from the git remote:

```bash
git remote get-url origin | grep -qi 'gitlab'
```
