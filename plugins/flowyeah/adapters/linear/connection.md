# Linear Connection

Shared setup for all Linear adapters.

## Config (`flowyeah.yml`)

```yaml
adapters:
  linear:
    team: Engineering       # optional — if missing, ask at runtime when creating issues
    on_start:               # optional — transition issue status when starting work
      status: In Progress   # Linear workflow state name
      mode: always          # always | ask
```

Linear uses the MCP integration for API access. Optional config keys:

- **`team`** — used when creating issues (`issues.adapter: linear`). If omitted, the pipeline asks at runtime.
- **`on_start.status`** — Linear workflow state to transition to when starting work on an issue (Step 3). Must match a status in the team's workflow. Required if `on_start` is present.
- **`on_start.mode`** — `always` = transition silently; `ask` = prompt before transitioning. Default: `always`.

If `on_start` is absent, no status transition happens (backward compatible).

## Prerequisites

**The Linear MCP plugin MUST be available.** Before any Linear operation, verify:

```
mcp__plugin_linear_linear__list_teams(limit: 1)
```

If this call fails or the tool is not found, **STOP immediately** and tell the user:

> Linear MCP plugin is not available. Install and enable the Linear plugin in Claude Code settings before using the Linear adapter.

Do NOT attempt to fall back to API calls or other workarounds.

## Authentication

Linear access is via the Claude Code Linear plugin (MCP). The plugin must be enabled in Claude Code settings.

No tokens or API keys to manage — MCP handles authentication.

## API Access

All Linear operations use MCP tools:

```
mcp__plugin_linear_linear__<operation>(...)
```

## Detecting Linear

Linear is detected from the source command prefix (`linear:XX-123`), not from the git remote.

## Write Operations Safety

MCP insulates the agent from raw HTTP failures, but it does **not** eliminate the write-uncertainty problem. MCP calls can time out, return errors, or succeed silently with unexpected payloads — and in all those cases the Linear-side write may have already happened.

**See also: `../_shared/write-safety.md`** for the transversal principle (parsing failure ≠ operation failure; verify before retry).

### Pass content directly to MCP tools — don't stage in shell

When calling `save_issue`, `save_comment`, etc. with multi-line descriptions, pass the markdown content **directly as the tool argument**, or read it from a file in the same MCP invocation. Do not stage it through a shell variable first:

- Wrong: build a markdown string in bash with heredoc, then pass `$VAR` into MCP. The same quoting/encoding bugs that hit curl-based adapters apply at the agent→MCP boundary.
- Right: write the content to a file with `Write`, then pass the content directly (the agent has the file open in context) or reference the file via the MCP tool's content parameter.

### MCP tool errors and timeouts ≠ operation failure

If `save_issue`, `save_comment`, or any other write tool errors, times out, or returns an unexpected response, **the write may have already landed on Linear**. Symptoms:

- The MCP call raises an error after a long pause (likely already committed).
- The response is missing `id`/`identifier` you expected (write may have happened with different fields).
- The tool returns a stale or unrelated payload (network/proxy issue between client and Linear).

NEVER call the same `save_*` tool again without verifying.

### Verify before retrying

Linear's `identifier` is server-assigned, so verification has to use other attributes. Order of preference:

1. **Title + team + recency** — `list_issues` filtered by team, ordered by `createdAt` desc, then post-filter for exact title equality and createdAt within the last few minutes.
2. **Body fingerprint** — if the body contains a unique string (a generated slug, commit SHA, link to a flowyeah session), filter on that.
3. **Assignee + recency** — if the write set an assignee, filter by assignee + recency.

```
mcp__plugin_linear_linear__list_issues(
  team: "<team>",
  limit: 10,
  orderBy: "createdAt"
)
```

Then, in the agent's reasoning (not via shell), keep entries where `title` equals the title sent and `createdAt` is within the last ~5 minutes.

- No matches → safe to retry the write.
- Exactly one match → record `identifier` and continue.
- Multiple matches with the same title → STOP and ask the user; there is already a duplicate.

This is **less reliable** than gitlab's `search` because Linear's identifier is post-write — there's an unavoidable window where two near-simultaneous writes look identical. If a verification round is ambiguous, stop and ask rather than guessing.

### No idempotency tokens

Linear's API does not accept client-side idempotency keys at this time. Verification is the only safety net; treat it as required, not optional.
