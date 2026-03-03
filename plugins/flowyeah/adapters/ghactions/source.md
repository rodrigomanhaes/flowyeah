# GitHub Actions Source Adapter

Fetches CI job logs from GitHub Actions and converts to canonical plan format for debugging.

**Connection:** See `connection.md` for authentication (uses `gh` CLI).

## Trigger

Two forms are accepted:

**Prefix form** (repo inferred from `gh repo view`):

```
ghactions:<job_id>
```

Example: `flowyeah:build from ghactions:12345678`

**Full URL form** (owner/repo parsed from URL):

```
https://github.com/{owner}/{repo}/actions/runs/{run_id}/job/{job_id}
```

Parse the URL to extract `owner`, `repo`, `run_id`, and `job_id`.

## Fetch Job Metadata

```bash
gh api repos/{owner}/{repo}/actions/jobs/{job_id}
```

**Fields to extract:**
- `name` — job name
- `status` — current status
- `conclusion` — final outcome (e.g., `failure`, `success`)
- `run_id` — parent workflow run ID
- `html_url` — direct link to the job in the GitHub UI
- `steps[]` — each step's `name` and `conclusion`

## Fetch Failed Log

```bash
gh run view {run_id} --log-failed
```

Returns only the log lines from failed steps. Use this output as the failure log in the plan.

## Fetch PR Context

```bash
gh api repos/{owner}/{repo}/actions/runs/{run_id} --jq '.pull_requests[0].number'
```

If a PR number is returned, store it as context. It is not used for workflow modification.

## Convert to Canonical Format

CI failures are always `fix` tasks — build a debugging-oriented plan:

```markdown
# Plan: Fix CI failure in <job_name> (ghactions:<job_id>)

## Context

- **Job:** <job_name>
- **Run:** <run_id>
- **Conclusion:** <conclusion>
- **PR:** #<pr_number> (if applicable)
- **Failed steps:** <step_names with conclusion=failure>

## Failure Log (abbreviated)

<relevant failure output — trim to the error and surrounding context,
 skip repetitive framework output, keep stack traces intact>

## Tasks
- [ ] Reproduce the failure locally
- [ ] Investigate root cause
- [ ] Implement fix
- [ ] Verify CI passes
```

The core skill should use `superpowers:systematic-debugging` for the investigation phase.

## Branch Naming

Use the last 6 digits of the job ID as slug: `fix/ci-<last_6_digits_of_job_id>`

Example: job ID `12345678` → `fix/ci-345678`

GitHub Actions failures are always `fix` type.

## Issue Linkage

Store these values in `state.md` for use throughout the pipeline:
- **Source:** `ghactions:<job_id>` — for state.md tracking
- **CI-Job:** `<html_url>` — direct link to the job
- **CI-PR:** `#<pr_number>` (if the run is associated with a PR)
- **Branch type override:** always `fix`

Note: CI logs do not support auto-close via merge keywords. No `Issue-Ref` or `Issue-Close` fields. The failure resolves when CI passes on a subsequent run.
