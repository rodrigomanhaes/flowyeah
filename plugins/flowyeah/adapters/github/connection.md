# GitHub Connection

Shared authentication and conventions for all GitHub adapters.

## Required Config (`flowyeah.yml`)

```yaml
adapters:
  github:
    # github uses gh CLI — no extra config needed
```

No adapter-specific config needed — `gh` uses the local git remote and GitHub authentication.

## Authentication

The `gh` CLI handles authentication. Verify:

```bash
gh auth status
```

If not authenticated, ask the user to run `gh auth login`.

## API Access

For operations not available through `gh` CLI subcommands, use the GitHub API directly:

```bash
gh api repos/{owner}/{repo}/endpoint
```

Detect owner/repo automatically:

```bash
gh repo view --json owner,name --jq '"\\(.owner.login)/\\(.name)"'
```

## Detecting GitHub

When auto-detecting the platform from the git remote:

```bash
git remote get-url origin | grep -qi 'github.com'
```
