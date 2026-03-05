# Linear Source Adapter

Fetches a Linear issue via MCP and converts it to canonical plan format.

**Connection:** See `connection.md` for MCP setup.

## Trigger

Command prefix: `linear:<identifier>`

Example: `flowyeah:build from linear:PROJ-123`

## Fetch Issue

```
mcp__plugin_linear_linear__get_issue(id: "<identifier>")
```

Where `<identifier>` is the full issue identifier (e.g., `PROJ-123`).

**Response fields to extract:**
- `title` — issue title
- `description` — issue body (markdown)
- `identifier` — issue identifier (e.g., `PROJ-123`)
- `labels` — array of label objects
- `state.name` — current status
- `priority` — priority level (1=Urgent, 2=High, 3=Normal, 4=Low)

## Sub-Issues

Check if the issue has sub-issues:

```
mcp__plugin_linear_linear__list_issues(parentId: "<issue_id>")
```

If sub-issues exist, use them as the task list.

## Convert to Canonical Format

**If the issue has sub-issues**, map them to tasks:

```markdown
# Plan: <title> (linear:<identifier>)

## Tasks
- [ ] Sub-issue title 1
- [ ] Sub-issue title 2
- [x] Completed sub-issue (state = Done/Completed)
```

**If the issue description contains a task list** (lines with `- [ ]` or `- [x]`), extract them:

```markdown
# Plan: <title> (linear:<identifier>)

## Tasks
- [ ] First task from description
- [ ] Second task from description
```

**If the issue description is prose** (no task list, no sub-issues), return the raw content. The core skill brainstorms with the user and generates a task plan.

## Create Issue

```
mcp__plugin_linear_linear__save_issue(
  title: "<title>",
  description: "<description>",
  team: "<team>"
)
```

The `team` is required when creating. Use `adapters.linear.team` from `flowyeah.yml` if configured; otherwise ask the user at runtime.

**Response fields:**
- `identifier` — issue identifier (e.g., `PROJ-456`)
- `url` — URL to show the user

After creation, use the returned `identifier` for branch naming and issue linkage as if the issue had been fetched.

## Branch Naming

The identifier becomes the branch slug: `<type>/<identifier>`

Example: `linear:PROJ-123` → `feat/PROJ-123`

## Issue Linkage

Store these values in `state.md` for use throughout the pipeline:
- **Issue-Ref:** `<identifier>` — appended in parentheses to PR/MR title
- **Source:** `linear:<identifier>` — for state.md tracking

Linear issues are not auto-closed by PR merge keywords. No `Issue-Close` field.

## On Start

When `adapters.linear.on_start` is configured in `flowyeah.yml`, transition the issue status after claiming (Step 3):

**When `mode: always`:**

```
mcp__plugin_linear_linear__save_issue(id: "<issue_id>", state: "<on_start.status>")
```

**When `mode: ask`:**

Prompt the user: "Move <identifier> to <on_start.status>?" If yes, call `save_issue`. If no, skip.

If `on_start` is not configured, skip this step entirely.