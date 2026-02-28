# GitHub Issue Source Adapter

Fetches a GitHub issue via `gh` CLI and converts it to canonical plan format.

## Trigger

Command prefix: `GITHUB:#<issue_number>`

Example: `/flowyeah from GITHUB:#45`

## Required Config (`flowyeah.yml` → `sources.github`)

```yaml
sources:
  github: {}
```

No adapter-specific config needed — `gh` uses the local git remote and GitHub authentication.

## Authentication

The `gh` CLI handles authentication. Verify:

```bash
gh auth status
```

## Fetch Issue

```bash
gh issue view <issue_number> --json title,body,labels,milestone,state
```

**Response fields to extract:**
- `title` — issue title
- `body` — issue body (markdown)
- `labels[].name` — label names
- `milestone.title` — milestone if assigned
- `state` — OPEN or CLOSED

## Convert to Canonical Format

**If the issue body contains a task list** (lines with `- [ ]` or `- [x]`), extract them:

```markdown
# Plan: <title> (GITHUB:#<issue_number>)

## Tasks
- [ ] First task from body
- [ ] Second task from body
- [x] Already completed task
```

**If the issue body is prose** (no task list), return the raw content. The core skill brainstorms with the user and generates a task plan.

## Branch Naming

The issue number becomes the branch slug: `<type>/<issue_number>`

Example: `GITHUB:#45` → `feat/45`

## Issue Linkage

Pass these values to the sink adapter:
- **Close keyword:** `Closes #<issue_number>` (for PR body)
- **Title suffix:** `(#<issue_number>)` (for PR title)
- **Source reference:** `GITHUB:#<issue_number>` (for state.md tracking)

GitHub auto-closes issues when a PR with `Closes #N` is merged into the default branch.
