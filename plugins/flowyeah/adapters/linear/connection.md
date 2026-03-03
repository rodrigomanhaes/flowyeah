# Linear Connection

Shared setup for all Linear adapters.

## Required Config (`flowyeah.yml`)

```yaml
adapters:
  linear:
    team: Engineering   # optional — if missing, ask at runtime when creating issues
```

Linear uses the MCP integration for API access. The only optional config is `team`, used when creating issues (`issues.adapter: linear`). If omitted, the pipeline asks at runtime.

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
