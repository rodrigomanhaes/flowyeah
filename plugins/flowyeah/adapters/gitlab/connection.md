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

**See also: `../_shared/write-safety.md`** for the transversal principle (parsing failure ≠ operation failure; verify before retry). The rules below implement that principle for GitLab's curl-based transport.

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

### Response handling for writes

When the server may have changed state, the response is forensic evidence. Treat it as such.

**Save the response to a file before parsing.** Never pipe `curl` output directly to a parser — if parsing fails, the original response is gone and you lose the ability to recover or verify:

```bash
TMPDIR_FY="${TMPDIR_FY:-$(mktemp -d -t flowyeah.XXXXXX)}"
curl -s --request POST -H "Authorization: Bearer $TOKEN" \
  --form-string "title=$TITLE" \
  --form-string "description=$DESC" \
  -w "\nHTTP %{http_code}\n" \
  "<url>/api/v4/projects/<project_id>/issues" \
  -o "$TMPDIR_FY/issue.json"
jq -r '"IID: \(.iid)\nURL: \(.web_url)"' "$TMPDIR_FY/issue.json"
```

`-o <file>` captures the body; `-w "\nHTTP %{http_code}\n"` prints the status code to stderr-ish stream after the file is written so you can confirm 2xx before parsing.

**Prefer `jq` over `python3` for parsing.** `jq` tolerates control characters and minor non-strict JSON that `python3 -c "import json; json.load(...)"` rejects outright. Reserve `python3` for transformations `jq` can't express.

**Use per-session temporary paths.** `$TMPDIR_FY` (or `$(mktemp -d)`) prevents collisions when multiple `flowyeah:build` or `flowyeah:respond` sessions run in parallel. Never hardcode `/tmp/issue.json` and similar.

### Parsing failure does not mean operation failure

If a POST/PUT/DELETE returns a non-2xx status, the operation failed and it is safe to retry after fixing the cause.

If a POST/PUT/DELETE returns 2xx but the response body fails to parse, or the curl call itself timed out / errored after sending the request, **the operation may have succeeded**. You don't know. NEVER retry blindly — that is exactly how duplicate issues and MRs get created.

Verify state before retrying. For GitLab issues:

```bash
# Verify by exact title match — GitLab's search is fuzzy (substring),
# so post-filter with jq for equality.
TITLE="<exact title that was sent>"
ENCODED=$(jq -rn --arg t "$TITLE" '$t|@uri')
curl -s -H "Authorization: Bearer $TOKEN" \
  "<url>/api/v4/projects/<project_id>/issues?search=$ENCODED&in=title&state=opened" \
  -o "$TMPDIR_FY/check.json"
jq --arg t "$TITLE" '[.[] | select(.title == $t) | {iid, web_url}]' "$TMPDIR_FY/check.json"
```

- Empty array → the write didn't land; safe to retry.
- Exactly one match → record the `iid` and continue as if the original write succeeded.
- More than one match → STOP and ask the user; you already had a duplicate before this incident.

Apply the same pattern for MRs (`/merge_requests?search=...`), notes (search by body substring + author), and labels (list and filter by exact name).
