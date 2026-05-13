# GitLab Connection

Shared authentication and API conventions for all GitLab adapters.

## Required Config (`flowyeah.yml`)

GitLab config lives under `adapters.gitlab`:

```yaml
adapters:
  gitlab:
    url: https://gitlab.example.com
    token_env: GITLAB_TOKEN
    token_source: .env
    project_id: 123
```

The same config is used whether GitLab is a source, git host, or both.

## Authentication

Extract the token directly from the configured file. **Do NOT `source` the file** — it may not work correctly in subshells:

```bash
TOKEN=$(grep "^<token_env>=" <token_source> | cut -d= -f2- | tr -d '"')
```

All API calls use:

```bash
curl -s -H "Authorization: Bearer $TOKEN"
```

## Base URL

```
<url>/api/v4/projects/<project_id>
```

All endpoints in source, git host, and review adapters are relative to this base.

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

**Exception:** The discussions API (used by `review.md`) requires JSON with `Content-Type: application/json` because the `position` parameter is a nested object that can't be expressed with `--form`.

## Detecting GitLab

When auto-detecting the platform from the git remote:

```bash
git remote get-url origin | grep -qi 'gitlab'
```

## Write Safety

Every write (POST/PUT/DELETE) against GitLab creates or alters a real resource in the project — issues, MRs, notes, labels — visible to the whole team and permanent in the project history. Follow these rules for all write operations in source, hosting, review, and respond adapters.

**Never use a mutating endpoint as a smoke test.** Do not POST/PUT/DELETE to verify auth, token validity, encoding, multipart syntax, or connectivity. Use a read-only endpoint:

```bash
curl -s -H "Authorization: Bearer $TOKEN" -w "\nHTTP %{http_code}\n" "<url>/api/v4/user"
```

If `GET /user` returns the expected user JSON with HTTP 200, auth and connectivity are fine; any failure in a subsequent write is in the payload, headers, or endpoint — not in the connection.

**Never escalate from a failing write to a different write.** When a POST/PUT/DELETE fails with cryptic output (silent failure, ambiguous error, empty body), do NOT retry with a simpler payload, a `title=Test` smoke value, or a different endpoint to "isolate the problem." That creates real garbage resources you then have to delete, polluting the project. Diagnose with verbose flags on the *same* call instead:

```bash
curl --request POST \
  -H "Authorization: Bearer $TOKEN" \
  --fail-with-body \
  -w "\nHTTP %{http_code}\n" \
  -v \
  --form ... \
  "<url>/api/v4/.../endpoint" 2>&1 | tail -40
```

`-v` exposes request/response headers; `--fail-with-body` exits nonzero on 4xx/5xx while still printing the body; `-w "HTTP %{http_code}"` prints the final status code. This shows the real failure cause without creating any resource.

### Multi-line or special-character values

`--form "field=<@file"` (read value from file) is fragile with markdown, code blocks, or any payload containing `@`, `<`, `;`, or quotes. For text values longer than one line or containing special characters, use `--form-string`:

```bash
DESC=$(cat /tmp/issue-body.md)
curl -s --request POST -H "Authorization: Bearer $TOKEN" \
  --form-string "title=Cadastro falha com Professor selecionado" \
  --form-string "description=$DESC" \
  "<url>/api/v4/projects/<project_id>/issues"
```

`--form-string` disables `@`/`<` interpretation in the value, so arbitrary markdown is safe. Reach for it before any single-line `--form "..."` workaround.
