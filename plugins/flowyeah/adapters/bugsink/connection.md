# Bugsink Connection

Shared authentication and API conventions for all Bugsink adapters.

## Required Config (`flowyeah.yml`)

```yaml
adapters:
  bugsink:
    url: https://bugsink.example.com
    token_env: BUGSINK_TOKEN
    token_source: .env
    on_merge:              # optional — resolve/comment when flowyeah merges the fix
      resolve: always      # always | ask | never
      comment: always      # always | never
```

- **`on_merge.resolve`** — `always` resolves the issue via the API (`resolve-next/` — "resolved by the next release") when flowyeah merges the fix; `ask` prompts first; `never` skips. Default when `on_merge` is absent: no resolve. Requires releases configured in the SDK — see `source.md` → "On Merge".
- **`on_merge.comment`** — `always` posts a traceability comment on merge; `never` skips. Default when `on_merge` is absent: no comment.

`on_merge` only fires when the build source was `bugsink:<id>` and flowyeah performed the merge (see `source.md` → "On Merge"). If `on_merge` is absent, no write happens (backward compatible).

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

## Write Safety

The adapter performs two writes on merge (see `source.md` → "On Merge"):
resolving an issue and posting a comment. Both alter real state on a live
Bugsink instance. Follow the curl tactics from `../gitlab/connection.md` →
"Write Safety" and the transversal principle in `../_shared/write-safety.md`:

- Save each response to a per-session file (`$TMPDIR_FY/...`) before parsing;
  parse with `jq`, not `python3`; print `-w "\nHTTP %{http_code}\n"` and
  confirm a 2xx before trusting the body.
- Never use a mutating endpoint as a smoke test. Verify auth with a read-only
  call (`GET /api/canonical/0/issues/<id>/`) instead.

Operation-specific reality (per the Bugsink API reference):

- **`POST /issues/{id}/resolve-next/`** ("resolved by the next release") is
  idempotent — re-resolving returns 200 with `is_resolved_by_next_release:
  true`. It is also one-way via the API: there is no unresolve/reopen endpoint
  (reopening is UI-only, or automatic when the error recurs in a later release).
  It requires the project to send a `release` identifier with events; without
  releases Bugsink cannot anchor a "next release" and the resolution degrades
  toward a plain resolve. Safe to retry on an ambiguous failure.
- **`POST /issue-comments/`** has no list/GET and no DELETE endpoint. A posted
  comment cannot be read back to verify, and cannot be deleted. On a
  2xx-but-unparseable response or a timeout, do **not** blind-retry — that
  duplicates the comment with no cleanup path. Report the ambiguous result and
  tell the user to check the issue in the Bugsink UI.
