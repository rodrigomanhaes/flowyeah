# Adapters

Platform integrations, shared by every flowyeah skill. A skill reads the adapter files it needs and follows their instructions — the adapters are prose and command templates, never executed as scripts.

**Config lookup rule:** all adapter config lives under `adapters.<name>` in `flowyeah.yml`, whether the adapter is used as a source, a git host, or both. Each adapter's own keys are declared in `adapters/<name>/config-schema.md`.

## Layout

```
adapters/
├── gitlab/
│   ├── connection.md      # Auth, base URL, --form encoding
│   ├── config-schema.md   # Keys valid under adapters.gitlab
│   ├── source.md          # Fetch issue → canonical format
│   ├── hosting.md         # Create MR, poll CI, merge
│   ├── review.md          # Fetch MR, post formal review
│   └── respond.md         # Fetch/reply/resolve review threads
├── github/
│   ├── connection.md      # gh CLI auth
│   ├── config-schema.md   # Keys valid under adapters.github (none)
│   ├── source.md          # Fetch issue → canonical format
│   ├── hosting.md         # Create PR, poll CI, merge
│   ├── review.md          # Fetch PR, post formal review
│   └── respond.md         # Fetch/reply/resolve review threads
├── linear/
│   ├── connection.md      # MCP setup
│   ├── config-schema.md   # Keys valid under adapters.linear
│   └── source.md          # Fetch issue → canonical format
├── bugsink/
│   ├── connection.md      # API token auth
│   ├── config-schema.md   # Keys valid under adapters.bugsink
│   └── source.md          # Fetch error → canonical format
├── newrelic/
│   ├── connection.md      # NerdGraph auth
│   ├── config-schema.md   # Keys valid under adapters.newrelic
│   └── source.md          # Fetch error group → canonical format
├── ghactions/
│   ├── connection.md      # gh CLI auth
│   ├── config-schema.md   # Keys valid under adapters.ghactions (none)
│   └── source.md          # Fetch CI job logs → canonical format
└── _shared/
    └── write-safety.md    # Transversal principle for all write operations
```

Each integration directory contains:
- **`connection.md`** — shared authentication, base URL, encoding conventions
- **`config-schema.md`** — the keys valid under `adapters.<name>` (empty table = no keys allowed)
- **`source.md`** — fetch data and convert to canonical format
- **`hosting.md`** — create PR/MR, poll CI, merge
- **`review.md`** — fetch PR/MR details, post formal review with inline comments
- **`respond.md`** — fetch review threads, reply, resolve, re-request review

`_shared/` holds rules that apply across all adapters regardless of transport. Each adapter's `connection.md` cross-references it where relevant.

**Adding a new integration:** create an adapter directory with `connection.md` + the adapter types you need, add config to `flowyeah.yml`. No changes to core skills.
