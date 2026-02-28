# Linear Connection

Shared setup for all Linear adapters.

## Required Config (`flowyeah.yml`)

```yaml
sources:
  linear: {}
```

No adapter-specific config needed — Linear uses the MCP integration.

## Authentication

Linear access is via the Claude Code Linear plugin (MCP). The plugin must be enabled in Claude Code settings.

No tokens or API keys to manage — MCP handles authentication.

## API Access

All Linear operations use MCP tools:

```
mcp__plugin_linear_linear__<operation>(...)
```

## Detecting Linear

Linear is detected from the source command prefix (`LINEAR:XX-123`), not from the git remote.
