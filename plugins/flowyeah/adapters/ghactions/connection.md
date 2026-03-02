# GitHub Actions Connection

Shared authentication for the GitHub Actions adapter.

## Required Config (`flowyeah.yml`)

```yaml
adapters:
  ghactions:
    # Uses gh CLI — no extra config needed
```

No adapter-specific config needed. Authentication and API access are handled by the GitHub adapter.

## Authentication

See `adapters/github/connection.md` for `gh` CLI authentication and API access patterns.

## Detecting GitHub Actions

Detected from:
- Command prefix: `GHACTIONS:<job_id>`
- Full URL: `https://github.com/{owner}/{repo}/actions/runs/{run_id}/job/{job_id}`
