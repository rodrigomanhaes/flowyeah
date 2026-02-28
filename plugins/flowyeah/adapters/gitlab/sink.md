# GitLab Sink Adapter

Creates merge requests, polls CI, and merges via the GitLab API.

**Connection:** See `connection.md` for authentication and API conventions.

## Create Merge Request

**Endpoint:** `POST /projects/<project_id>/merge_requests`

**Use `--form` encoding** (see connection.md for why):

```bash
TOKEN=$(grep "^<token_env>=" <token_source> | cut -d= -f2- | tr -d '"') && \
curl -s --request POST -H "Authorization: Bearer $TOKEN" \
  --form "source_branch=<source_branch>" \
  --form "target_branch=<target_branch>" \
  --form "title=<title>" \
  --form "description=<body>" \
  --form "remove_source_branch=<delete_source_branch>" \
  "<url>/api/v4/projects/<project_id>/merge_requests"
```

**Response fields:**
- `iid` — MR number (for display and linking)
- `web_url` — URL to show the user
- `pipeline.id` — pipeline ID (if CI triggered immediately)

Save `iid` and `web_url` for later steps.

## Poll CI Status

**Endpoint:** `GET /projects/<project_id>/merge_requests/<iid>/pipelines`

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "<url>/api/v4/projects/<project_id>/merge_requests/<iid>/pipelines" | jq '.[0]'
```

**Pipeline status values:**
- `success` → CI passed, proceed
- `failed` → CI failed, investigate
- `running` / `pending` → still in progress, wait and re-poll
- `canceled` → treat as failure

**Poll interval:** 30 seconds. **Timeout:** after 10 minutes of polling, ask the user whether to keep waiting.

### Reading CI Failure Details

When pipeline status is `failed`, get the failing job logs:

**Step 1 — List jobs:**
```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "<url>/api/v4/projects/<project_id>/pipelines/<pipeline_id>/jobs" | \
  jq '.[] | select(.status == "failed") | {id, name, stage}'
```

**Step 2 — Read job trace (log):**
```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "<url>/api/v4/projects/<project_id>/jobs/<job_id>/trace"
```

Use the trace output to diagnose the failure.

## Merge

**Endpoint:** `PUT /projects/<project_id>/merge_requests/<iid>/merge`

```bash
curl -s --request PUT -H "Authorization: Bearer $TOKEN" \
  --form "squash=<true if merge_strategy is squash, false otherwise>" \
  --form "should_remove_source_branch=<delete_source_branch>" \
  "<url>/api/v4/projects/<project_id>/merge_requests/<iid>/merge"
```

**Response:** check `state` field — should be `merged`.

**Limitation:** GitLab's merge API only supports `squash` and regular merge. The `rebase` strategy is a project-level setting — it cannot be requested per merge request via API. If `merge_strategy: rebase` is set, warn the user that GitLab will use a regular merge unless the project is configured for rebase merges in GitLab settings.

If merge fails (e.g., conflicts), report the error and ask the user.

## Update MR (optional)

If you need to update the MR after pushing fixes:

```bash
curl -s --request PUT -H "Authorization: Bearer $TOKEN" \
  --form "title=<new_title>" \
  "<url>/api/v4/projects/<project_id>/merge_requests/<iid>"
```

## Issue Linking

When the source was a GitLab issue, include `Closes #<issue_number>` in the MR description. GitLab auto-closes the issue on merge.

For MR title, append `(#<issue_number>)` at the end.
