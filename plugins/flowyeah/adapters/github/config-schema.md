# github Adapter Config Schema

Declares the keys valid under `adapters.github` in flowyeah.yml.
Exhaustive — any key not listed here is unknown.

## Keys

| Key | Required | Default | Values | Notes |
|-----|----------|---------|--------|-------|

No keys. The GitHub adapter authenticates and resolves the repository
through the `gh` CLI; an `adapters.github` block only marks the adapter as
available. Any key placed under it is flagged as unknown by `flowyeah:check`.
