# GitLab Source Adapter

Fetches a GitLab issue and converts it to canonical plan format.

**Connection:** See `connection.md` for authentication and API conventions.

## Trigger

Command prefix: `GITLAB:#<issue_number>`

Example: `/flowyeah from GITLAB:#5588`

## Fetch Issue

**Endpoint:** `GET /projects/<project_id>/issues/<issue_number>`

```bash
TOKEN=$(grep "<token_env>" <token_source> | cut -d= -f2) && \
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
# Plan: <title> (GITLAB:#<iid>)

## Tasks
- [ ] First task from description
- [ ] Second task from description
- [x] Already completed task
```

**If the issue description is prose** (no task list), return the raw content to the core skill. The core skill will brainstorm with the user and generate a task plan.

## Branch Naming

The issue number becomes the branch slug: `<type>/<iid>`

Example: `GITLAB:#5588` → `feat/5588`

## Issue Linkage

Pass these values to the sink adapter:
- **Close keyword:** `Closes #<iid>` (for MR description)
- **Title suffix:** `(#<iid>)` (for MR title)
- **Source reference:** `GITLAB:#<iid>` (for state.md tracking)
