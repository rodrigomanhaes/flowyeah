---
name: check
description: Audit flowyeah.yml against the config schema — reports errors, warnings, deprecated keys, and absent optional fields with their defaults
---

# flowyeah:check — Configuration Audit

Read-only audit of `flowyeah.yml` against the config schema; never mutates the file. May offer one follow-up question to fill in absent optional adapter keys (see Behavior).

```
flowyeah:check
```

## Prerequisites

`flowyeah.yml` must exist in the project root. If missing, tell the user and suggest running `flowyeah:build` or `flowyeah:review` to trigger interactive setup.

## Process

1. Load `config-schema.md` from the plugin root (all three sections: Current Schema, Validation Rules, Deprecated Keys)
2. Load the user's `flowyeah.yml` from the project root
3. For each adapter present under `adapters.<name>`, load `adapters/<name>/config-schema.md` if it exists (absent = adapter has no declared keys; nothing to validate or suggest)
4. Produce annotated full YAML (primary output)
5. Produce summary report (secondary output)

## Annotated YAML

Show every key from the "Current Schema" section, with the user's value or the default. Mark each line with:

| Marker | Meaning |
|--------|---------|
| `# ✅` | Explicitly set in file |
| `# ⬚ default: <value>` | Absent, using default |
| `# ⚠ deprecated — <migration hint>` | Key present but deprecated |
| `# ⚠ unknown key` | Adapter key present but not declared in its `config-schema.md` |
| `# ❌ <error message>` | Validation error |

For each adapter with a `config-schema.md`, expand every declared key and mark it like core keys: `✅` if set, `⬚ default: <value>` if an optional key is absent. Apply the adapter validation rules: a required key absent is `❌`; an enum value outside its allowed set is `❌`; a key present but not declared is `⚠ unknown key`. For an adapter without a `config-schema.md`, show whatever the user has under `adapters.<name>` marked `✅` (no validation).

### Example

```yaml
# flowyeah.yml — full configuration
# ✅ = set in file  ⬚ = using default  ⚠ = deprecated / unknown key  ❌ = error

language: pt-br                          # ✅

git:
  default_branch: develop                # ✅

testing:
  command: bundle exec rspec             # ✅
  scope: related                         # ⬚ default: related

implementation:
  brainstorm: always                     # ✅
  approval: auto                         # ⬚ default: auto
  process_skills:                        # ⬚ not configured
    brainstorming:                       # ⬚ not configured
    planning:                            # ⬚ not configured
    tdd:                                 # ⬚ not configured
    debugging:                           # ⬚ not configured

commits:
  conventions: conventional              # ⬚ default: conventional
  writer: null                           # ⬚ default: null (write inline)

pull_requests:
  delete_source_branch: true             # ✅
  rebase: true                           # ⬚ default: true
  merge: manual                          # ✅
  merge_strategy: squash                 # ⬚ default: squash

code_review:
  agents:                                # ✅
    - pr-review-toolkit:code-reviewer
    - pr-review-toolkit:silent-failure-hunter
  optional_agents: []                    # ⬚ default: []
  instructions: .flowyeah/review.md     # ✅   (or: # ⬚ not configured)
  evaluation_skill:                      # ⬚ not configured
  impact_analysis:                       # ⬚ not configured (built-in tracing runs)

issues:
  create_when_missing: ask               # ✅
  adapter:                               # ❌ required when create_when_missing is 'ask'

worktree:
  symlinks: []                           # ⬚ default: []
  env: []                                # ⬚ default: []
  setup: []                              # ⬚ default: []
  teardown: []                           # ⬚ default: []

hooks:
  pr:
    after_create:                        # ⬚ not configured
    after_merge:                         # ⬚ not configured

adapters:
  gitlab:                                # ✅
    url: https://gitlab.example.com      # ✅
    token_env: GITLAB_TOKEN              # ✅
    token_source: .env                   # ✅
    project_id: 123                      # ✅
  bugsink:                               # ✅
    url: https://bugsink.example.com     # ✅
    token_env: BUGSINK_TOKEN             # ✅
    token_source: .env                   # ✅
    on_merge:
      resolve:                           # ⬚ default: absent (skip)
      comment:                           # ⬚ default: absent (skip)

git_host: gitlab                         # ✅

sources:                                 # ⚠ deprecated — remove, adapters with source.md are automatic sources
  - gitlab
```

## Summary Report

After the annotated YAML, produce:

```
Errors (N):
  <key> — <message>

Warnings (N):
  <key> — <migration hint>

Optional (N):
  <key1>, <key2>, <key3>, ...
```

- **Errors:** validation failures from the "Validation Rules" section — core keys and adapter keys (required adapter key absent, invalid adapter enum value)
- **Warnings:** deprecated keys from the "Deprecated Keys" section, and unknown adapter keys (present but not declared in the adapter's config-schema.md)
- **Optional:** absent keys that have defaults (the `⬚` lines) — core keys and absent optional adapter keys

## Behavior

- The audit is read-only and never mutates the file: report problems, don't fix them.
- After the report, if there are **absent optional adapter keys** (⬚ lines under an adapter), make exactly one offer: list them and ask whether to fill them in now. On yes, enter setup's Reconcile Mode (see `setup.md` → "Reconcile Mode"), passing the adapter name(s) and the absent optional keys. On no, stop — nothing is mutated. Errors and warnings are reported only, never auto-fixed and never part of the offer.
- Run validation rules from the "Validation Rules" section of `config-schema.md`.
- Check for deprecated keys from the "Deprecated Keys" section.
- List all absent keys that have defaults in the "Optional" category.
