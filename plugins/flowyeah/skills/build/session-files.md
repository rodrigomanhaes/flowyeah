# Session files

The four files `flowyeah:build` writes into `.flowyeah/` inside its worktree at step 3. Read this when creating them, and when a resumed session needs to know what a field means. The `progress.md` schema stays in `SKILL.md` — every GATE names its checklist items.

Session state survives context compaction (via hook injection) and crashes (the files persist on disk). It is removed with the worktree at step 10.

### state.md — Rich Context (update very frequently)

Must have parseable header lines for crash recovery summaries:

```markdown
# Current State

Type: build
Status: Implementing
Step: 4 (Implement) — TDD phase
Mode: single                          # single | continuous
Task: Webhook retry logic
Source: gitlab:#5588
Plan: tmp/flowyeah/plans/gitlab-5588.md  # relative to main checkout
Branch: feat/5588
Worktree: .flowyeah/worktrees/feat-5588
Issue-Ref: #5588                      # from source adapter's Issue Linkage
Issue-Close: Closes #5588             # close keyword for PR/MR body
Investigation: intermittent            # set in Step 3 when --intermittent flag is passed
On-Branch: true                       # set in Step 3 when --on-branch flag is passed

## Worktree Env
DB_SUFFIX=kM4tQ8hN
REDIS_DB=pL7nR2wY

## Key Decisions Made
- Chose exponential backoff over linear retry (better for rate-limited APIs)
- Max 5 retries with jitter to avoid thundering herd
- Using ActiveJob retry mechanism rather than custom loop

## What's Been Done
- Brainstormed 3 approaches
- Plan: 4 implementation steps
- Steps 1-2 complete: model and service layer
- Step 3 in progress: controller integration

## Dead Ends
- Tried custom retry loop with sleep — race condition with Sidekiq's own retry
- Tried rescue_from in controller — too late, webhook already marked as failed

## Current Focus
Writing failing feature spec for webhook retry behavior.

## Next Action
Complete the feature spec, then implement the controller action.
```

**Update when:** every pipeline step transition, every phase transition within step 4, after completing subtasks, after discovering dead ends, after making key decisions. The more context here, the better a resumed session performs.

### mission.md — Goal (update rarely)

```markdown
# Mission

Implement webhook retry with exponential backoff for failed deliveries.

## Scope
- Retry mechanism with configurable max attempts
- Exponential backoff with jitter
- Dead letter queue for permanently failed webhooks
- Admin UI to view retry status

## Success Criteria
- [ ] Failing webhooks are retried up to 5 times
- [ ] Backoff is exponential with jitter
- [ ] Permanently failed webhooks go to dead letter queue
- [ ] Admin can see retry history
- [ ] All tests pass, CI green
```

### findings.md — Accumulated Knowledge (update after discoveries)

```markdown
# Findings

## Summary
ActiveJob's retry_on has a quirk: exponential backoff is capped at
the job's max wait time, not the retry count. Set both explicitly.

## Details

### ActiveJob retry_on gotcha
The `wait` parameter in retry_on accepts a lambda but the exponential
calculation is capped by `retry_jitter` config. Must set both:
  retry_on WebhookError, wait: :polynomially_longer, attempts: 5
  self.retry_jitter = 0.15
```

Keep `## Summary` current — the injection hook only shows the summary section, not full details.

### Hook-Based Injection

Two hooks (installed via this plugin's `hooks/hooks.json`) power session recovery:

1. **`UserPromptSubmit`** — `session-inject.sh` injects all 4 files on every prompt (findings: summary only). This is how state survives context compaction.

2. **`PostToolUse` on Edit/Write** — `session-remind.sh` nudges to update state.md after making changes.

Both scripts are guarded: exit silently if no `flowyeah.yml` in project or no active `.flowyeah/` session.

### Context Compaction Recovery

After compaction, the hook re-injects state automatically:
1. Read injected state to find current position
2. Continue from where `state.md` indicates
3. Do NOT restart the task from scratch
