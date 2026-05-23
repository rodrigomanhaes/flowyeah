# GitLab Source Adapter

Fetches a GitLab issue and converts it to canonical plan format.

**Connection:** See `connection.md` for authentication and API conventions.

## Trigger

Command prefix: `gitlab:#<issue_number>`

Example: `flowyeah:build from gitlab:#5588`

## Fetch Issue

**Endpoint:** `GET /projects/<project_id>/issues/<issue_number>`

```bash
TOKEN=$(grep "^<token_env>=" <token_source> | cut -d= -f2- | tr -d '"') && \
curl -s -H "Authorization: Bearer $TOKEN" \
  "<url>/api/v4/projects/<project_id>/issues/<issue_number>"
```

**Response fields to extract:**
- `title` — issue title
- `description` — issue body (markdown)
- `iid` — issue number
- `labels` — array of label names
- `milestone.title` — milestone if assigned

## Convert to Canonical Format

**If the issue description contains a task list** (lines with `- [ ]` or `- [x]`), extract them directly:

```markdown
# Plan: <title> (gitlab:#<iid>)

## Tasks
- [ ] First task from description
- [ ] Second task from description
- [x] Already completed task
```

**If the issue description is prose** (no task list), return the raw content to the core skill. The core skill will brainstorm with the user and generate a task plan.

## Create Issue

**Endpoint:** `POST /projects/<project_id>/issues`

Follow `connection.md` → "Write Safety" and "Response handling for writes". Summary applied here:

1. Multi-line description goes via file + `--form-string` (never via `--form "x=@file"`, which makes a multipart file upload).
2. Response captured to a per-session tempfile so verification is possible if parsing fails.
3. If parsing fails, verify before retrying — see "If create appears to fail" below.

```bash
# 0. Per-session scratch dir (reuse if already exported by the build session)
TMPDIR_FY="${TMPDIR_FY:-$(mktemp -d -t flowyeah.XXXXXX)}"

# 1. Token + current user (for assignment)
TOKEN=$(grep "^<token_env>=" <token_source> | cut -d= -f2- | tr -d '"')
USER_ID=$(curl -s -H "Authorization: Bearer $TOKEN" "<url>/api/v4/user" -o "$TMPDIR_FY/user.json" \
  && jq -r '.id' "$TMPDIR_FY/user.json")

# 2. Write the description to a file (multi-line, code blocks, $vars, quotes all safe)
cat > "$TMPDIR_FY/issue-desc.md" <<'EOF'
<description content here — anything goes, no escaping needed>
EOF

# 3. Create the issue — capture response to a file, print HTTP status
TITLE="<title>"
DESC=$(cat "$TMPDIR_FY/issue-desc.md")
curl -s --request POST -H "Authorization: Bearer $TOKEN" \
  --form-string "title=$TITLE" \
  --form-string "description=$DESC" \
  --form "assignee_ids[]=$USER_ID" \
  -w "\nHTTP %{http_code}\n" \
  "<url>/api/v4/projects/<project_id>/issues" \
  -o "$TMPDIR_FY/issue.json"

# 4. Parse the response with jq (not python — jq tolerates more)
jq -r '"IID: \(.iid)\nURL: \(.web_url)"' "$TMPDIR_FY/issue.json"
```

**Response fields:**
- `iid` — issue number (use for linkage)
- `web_url` — URL to show the user

After creation, use the returned `iid` for branch naming and issue linkage as if the issue had been fetched.

### If create appears to fail

If step 4 errors (parse failure, missing fields) or step 3 prints a non-2xx status, **do not re-run step 3 blindly** — the issue may already exist. Verify first:

```bash
ENCODED=$(jq -rn --arg t "$TITLE" '$t|@uri')
curl -s -H "Authorization: Bearer $TOKEN" \
  "<url>/api/v4/projects/<project_id>/issues?search=$ENCODED&in=title&state=opened" \
  -o "$TMPDIR_FY/check.json"
jq --arg t "$TITLE" '[.[] | select(.title == $t) | {iid, web_url}]' "$TMPDIR_FY/check.json"
```

- **Empty array** → the create did not land; safe to retry step 3.
- **One match** → reuse that `iid`; do not retry.
- **More than one** → STOP and ask the user; there was already a duplicate before this attempt.

## Branch Naming

The issue number becomes the branch slug: `<type>/<iid>`

Example: `gitlab:#5588` → `feat/5588`

## Issue Linkage

Store these values in `state.md` for use throughout the pipeline:
- **Issue-Ref:** `#<iid>` — appended in parentheses to PR/MR title
- **Issue-Close:** `Closes #<iid>` — included in PR/MR body for auto-close
- **Source:** `gitlab:#<iid>` — for state.md tracking
