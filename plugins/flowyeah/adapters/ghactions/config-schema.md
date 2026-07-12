# ghactions Adapter Config Schema

Declares the keys valid under `adapters.ghactions` in flowyeah.yml.
Exhaustive — any key not listed here is unknown.

## Keys

| Key | Required | Default | Values | Notes |
|-----|----------|---------|--------|-------|

No keys. The GitHub Actions adapter authenticates through the `gh` CLI and
takes run/job identity from the source argument; an `adapters.ghactions`
block only marks the adapter as available. Any key placed under it is
flagged as unknown by `flowyeah:check`.
