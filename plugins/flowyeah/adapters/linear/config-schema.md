# linear Adapter Config Schema

Declares the keys valid under `adapters.linear` in flowyeah.yml.
Exhaustive — any key not listed here is unknown.
Linear uses MCP for API access — no url/token keys.

## Keys

| Key | Required | Default | Values | Notes |
|-----|----------|---------|--------|-------|
| `team` | no | ask at runtime | string | Team for issue creation (`issues.adapter: linear`) |
| `on_start.status` | if `on_start` set | — | string | Linear workflow state to transition to when starting work |
| `on_start.mode` | no | `always` | `always` \| `ask` | `always` = transition silently; `ask` = prompt first |

## Notes

- `on_start` is optional. If absent, no status transition happens. If present,
  `on_start.status` is required (`on_start.mode` still defaults to `always`).
