---
name: check
description: Audit flowyeah.yml against the config schema — reports errors, warnings, deprecated keys, and absent optional fields with their defaults
---

# flowyeah:check — Configuration Audit

Read-only audit of `flowyeah.yml` against the config schema. No interactive questions, no file mutations.

```
flowyeah:check
```

## Prerequisites

`flowyeah.yml` must exist in the project root. If missing, tell the user and suggest running `flowyeah:build` or `flowyeah:review` to trigger interactive setup.

## Process

1. Load `config-schema.md` from the plugin root (all three sections: Current Schema, Validation Rules, Deprecated Keys)
2. Load the user's `flowyeah.yml` from the project root
3. Produce annotated full YAML (primary output)
4. Produce summary report (secondary output)

## Annotated YAML

Show every key from the "Current Schema" section, with the user's value or the default. Mark each line with:

| Marker | Meaning |
|--------|---------|
| `# ✅` | Explicitly set in file |
| `# ⬚ default: <value>` | Absent, using default |
| `# ⚠ deprecated — <migration hint>` | Key present but deprecated |
| `# ❌ <error message>` | Validation error |

For adapter-specific keys (schema-free), show whatever the user has under `adapters.<name>` marked as `✅`. Don't validate adapter-internal keys — adapters own their own schema.

### Example

```yaml
# flowyeah.yml — full configuration
# ✅ = set in file  ⬚ = using default  ⚠ = deprecated  ❌ = error

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
    url: https://gitlab.example.com
    token_env: GITLAB_TOKEN
    token_source: .env
    project_id: 123

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

- **Errors:** validation failures from the "Validation Rules" section of the schema
- **Warnings:** deprecated keys from the "Deprecated Keys" section
- **Optional:** absent keys that have defaults (the `⬚` lines)

## Behavior

- Read-only. Report problems, don't fix them.
- No interactive questions, no file mutations.
- Run validation rules from the "Validation Rules" section of `config-schema.md`.
- Check for deprecated keys from the "Deprecated Keys" section.
- List all absent keys that have defaults in the "Optional" category.
