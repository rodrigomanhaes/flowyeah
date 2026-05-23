# Write Operations Safety (Shared)

Transversal rules for every adapter that creates, updates, or deletes resources
in an external system — issues, MRs/PRs, comments, status transitions,
releases, anything. Applies regardless of transport: `curl`, `gh`, MCP, SDKs.

Each adapter's `connection.md` has a "Write Operations Safety" section with
transport-specific tactics that implement this principle.

## The principle

> If a write operation's response is missing, malformed, ambiguous, or arrived
> after a timeout, the operation may have succeeded. You don't know its state.
> **Verify state before retrying. Never retry blindly.**

A duplicated issue, MR, comment, or release is almost always worse than a slow
retry, harder to detect than a hard failure, and pollutes shared project state
that other people see.

## Why this happens

Three layers can fail independently between you and a confirmed write:

1. **The request** — could be malformed, rejected, or never sent.
2. **The server-side write** — may have succeeded, partially succeeded, or failed.
3. **The response handling** — parsing, deserialization, or transport (timeout, broken pipe).

Layers 1 and 3 failing tell you **nothing** about layer 2. Treating a layer-3
failure (parsing error, timeout, broken pipe) as a layer-2 failure (write
didn't happen) is the bug that creates duplicates.

## What "verify state" means in practice

Before retrying any write, query the resource by an attribute the agent
already knows:

- **By exact title or identifier** — list resources filtered to a tight
  predicate, then post-filter for exact equality. Server-side search is often
  fuzzy; do the exact match client-side (`jq`, `--jq`, or in code).
- **By idempotent attribute** — if the create used a slug, branch name,
  external ID, or user-supplied identifier, query for that.
- **By recency** — last resort: list resources created in the last N seconds
  by the current user.

If the resource exists → the write succeeded; record the ID and continue.
If it doesn't exist → safe to retry.

## When verification is ambiguous: stop and ask

If the verification query returns multiple candidates and you can't
distinguish them, or no predicate is tight enough to be safe, **STOP and ask
Rodrigo**. Do not guess. A duplicate is worse than a paused pipeline.

## A note on idempotency

Most APIs flowyeah talks to (GitLab, Linear, Bugsink, New Relic) do not accept
client-side idempotency tokens. GitHub accepts them on a few endpoints but no
adapter currently sets them. Verification is the workaround for that gap; it
is not the ideal pattern.

If an adapter starts using an endpoint that supports idempotency tokens,
prefer that over verification and document the choice in the adapter's
`connection.md`.

## Per-transport tactics

See each adapter's `connection.md` → "Write Operations Safety" for concrete
patterns:

- `gitlab/connection.md` — curl with `--form-string`, response capture, `jq` parsing
- `github/connection.md` — `gh` CLI with `--body-file`, `gh api` output capture
- `linear/connection.md` — MCP-specific failure modes and verification
- `bugsink/connection.md` — curl tactics (Bugsink writes are rare but exist)
- `newrelic/connection.md` — NerdGraph (GraphQL) write tactics
