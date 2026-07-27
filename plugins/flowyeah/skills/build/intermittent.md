# `--intermittent` — investigating a flaky test

Reached from `flowyeah:build` when `--intermittent` is passed (step 3 sets `Investigation: intermittent` in `state.md`; step 4 follows the escalation below). The goal is to identify **why** a test fails intermittently, not to make it pass once.

## Step 3 — worktree placement

An intermittent failure investigation is **always independent** of the origin PR. Even when the source is a CI failure from a PR, the investigation starts fresh from the configured main branch, because intermittent failures are usually pre-existing issues that surfaced randomly on that run.

- **Always create the worktree from `$DEFAULT_BRANCH`** — never from the PR branch, never from `--on-branch`.
- **`--on-branch` is ignored when both are passed** — intermittent takes precedence. The investigation needs a clean main-branch environment.
- **Reproduce on main only.** Step 4's escape hatch covers the case where the failure turns out to be PR-specific.
- **The `CI-PR` field in `state.md` is informational** — it records where the failure was observed. The investigation and any resulting fix are separate from that PR.

Then follow the standard worktree creation flow in step 3, starting from `git fetch origin $DEFAULT_BRANCH`.

## Step 4 — escalation

**CI log source:** read the failure log from `mission.md`, where the source adapter persisted it during step 1. Do not re-fetch from the CI API — the original run may have been re-triggered and passed since, making the failure log unavailable. Session files are the authoritative source for the failure context.

Stop escalating as soon as the cause is found, then switch to the normal TDD fix cycle from step 4 with that cause as the failing-test starting point. All levels run on the main branch: intermittent failures are investigated where the codebase lives, not on a PR branch.

1. **Run the failing test in isolation.** Does it fail by itself? If yes, the failure is not intermittent — fall back to standard debugging. Invoke `process_skills.debugging` if configured (mandatory — same rule as other process skills).

2. **Check ordering dependency.** Run the full spec file (or suite) with the seed from the CI log (in `mission.md`). Reproduce the failure with the same test ordering.

3. **Analyze shared state.** Look for: database records leaking between tests, global variable mutation, file system side effects, time-dependent assertions (`Time.now`, `Date.today`), external service dependencies.

4. **Framework-specific bisect.** If the above don't reveal the cause:

   | `testing.command` contains | Bisect approach |
   |----------------------------|-----------------|
   | `rspec` | `rspec --bisect --seed <seed>` |
   | `pytest` | `pytest --randomly-seed=<seed>` + manual narrowing |
   | `jest` | `jest --runInBand` to isolate ordering effects |
   | Other | Report automated bisect is unavailable, suggest manual investigation |

5. **PR-caused failure escape hatch.** If levels 1–4 cannot reproduce the failure on main at all, and the source has a `CI-PR` field, the failure may not be intermittent — it may be caused by the PR's own changes. STOP the investigation and report: "Could not reproduce on main. This failure may be caused by the PR itself, not an intermittent issue." Let the user decide how to proceed.

6. **STOP and report.** If bisect or another level found evidence of intermittency but could not isolate the root cause, the problem may be infrastructure-level (timing, external services, resource contention). Present findings and ask for guidance.
