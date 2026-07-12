#!/bin/bash
# Tests for flowyeah hooks (session-inject.sh and session-remind.sh).
# Run from anywhere: bash plugins/flowyeah/tests/test-hooks.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../hooks" && pwd)"
PASS=0
FAIL=0
TOTAL=0

# ── Helpers ──────────────────────────────────────────────

setup_repo() {
    WORKDIR=$(mktemp -d)
    cd "$WORKDIR"
    git init -q -b main
    git commit --allow-empty -m "init" -q
}

teardown() {
    cd /
    rm -rf "$WORKDIR"
}

assert_output_contains() {
    local label="$1" pattern="$2" output="$3"
    TOTAL=$((TOTAL + 1))
    if echo "$output" | grep -qF "$pattern"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $label"
        echo "  expected to contain: $pattern"
        echo "  got: $output"
    fi
}

assert_output_not_contains() {
    local label="$1" pattern="$2" output="$3"
    TOTAL=$((TOTAL + 1))
    if echo "$output" | grep -qF "$pattern"; then
        FAIL=$((FAIL + 1))
        echo "FAIL: $label"
        echo "  expected NOT to contain: $pattern"
        echo "  got: $output"
    else
        PASS=$((PASS + 1))
    fi
}

assert_empty() {
    local label="$1" output="$2"
    TOTAL=$((TOTAL + 1))
    if [ -z "$output" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $label"
        echo "  expected empty output"
        echo "  got: $output"
    fi
}

assert_exit_zero() {
    local label="$1"
    TOTAL=$((TOTAL + 1))
    if [ "$2" -eq 0 ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $label (exit code: $2)"
    fi
}

assert_exit_eq() {
    local label="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$actual" -eq "$expected" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $label (expected exit $expected, got $actual)"
    fi
}

# ── session-remind.sh tests ─────────────────────────────

echo "=== session-remind.sh ==="

# Test: silent when no flowyeah session
setup_repo
OUTPUT=$(bash "$SCRIPT_DIR/session-remind.sh" 2>&1 || true)
assert_empty "remind: silent without session" "$OUTPUT"
teardown

# Test: silent when no git repo
WORKDIR=$(mktemp -d)
cd "$WORKDIR"
OUTPUT=$(bash "$SCRIPT_DIR/session-remind.sh" 2>&1 || true)
assert_empty "remind: silent outside git repo" "$OUTPUT"
cd /; rm -rf "$WORKDIR"

# Test: silent when state.md exists but no flowyeah.yml
setup_repo
mkdir -p .flowyeah
echo "# Current State" > .flowyeah/state.md
OUTPUT=$(bash "$SCRIPT_DIR/session-remind.sh" 2>&1 || true)
assert_empty "remind: silent without flowyeah.yml even with state.md" "$OUTPUT"
teardown

# Test: outputs reminder when build session is active
setup_repo
touch flowyeah.yml
mkdir -p .flowyeah
echo "# Current State" > .flowyeah/state.md
OUTPUT=$(bash "$SCRIPT_DIR/session-remind.sh" 2>&1)
assert_output_contains "remind: outputs reminder with build session" "Update .flowyeah/state.md" "$OUTPUT"
teardown

# Test: outputs reminder when review session is active
setup_repo
touch flowyeah.yml
mkdir -p .flowyeah
echo -e "# Current State\nBranch: main" > .flowyeah/review-state-42.md
OUTPUT=$(bash "$SCRIPT_DIR/session-remind.sh" 2>&1)
assert_output_contains "remind: outputs reminder with review session" "review-state-42.md" "$OUTPUT"
teardown

# ── session-inject.sh tests ─────────────────────────────

echo ""
echo "=== session-inject.sh ==="

# Test: silent when no flowyeah.yml
setup_repo
OUTPUT=$(bash "$SCRIPT_DIR/session-inject.sh" 2>&1 || true)
assert_empty "inject: silent without flowyeah.yml" "$OUTPUT"
teardown

# Test: silent when flowyeah.yml exists but no session
setup_repo
touch flowyeah.yml
OUTPUT=$(bash "$SCRIPT_DIR/session-inject.sh" 2>&1 || true)
assert_empty "inject: silent with flowyeah.yml but no session" "$OUTPUT"
teardown

# Test: injects build session state
setup_repo
touch flowyeah.yml
mkdir -p .flowyeah
cat > .flowyeah/state.md <<'EOF'
# Current State

Type: build
Status: Implementing
Step: 4
Task: Webhook retry
EOF
cat > .flowyeah/mission.md <<'EOF'
# Mission
Implement webhook retry logic.
EOF
cat > .flowyeah/progress.md <<'EOF'
# Progress
- [x] Design
- [ ] Implement
EOF
OUTPUT=$(bash "$SCRIPT_DIR/session-inject.sh" 2>&1)
assert_output_contains "inject: shows session type" "flowyeah:build session" "$OUTPUT"
assert_output_contains "inject: shows MISSION section" "## MISSION" "$OUTPUT"
assert_output_contains "inject: shows mission content" "Implement webhook retry" "$OUTPUT"
assert_output_contains "inject: shows PROGRESS section" "## PROGRESS" "$OUTPUT"
assert_output_contains "inject: shows progress content" "Design" "$OUTPUT"
assert_output_contains "inject: shows STATE section" "## STATE" "$OUTPUT"
assert_output_contains "inject: shows state content" "Webhook retry" "$OUTPUT"
assert_output_contains "inject: shows FINDINGS section" "## FINDINGS" "$OUTPUT"
teardown

# Test: review session uses review-state.md, skips MISSION, PROGRESS, FINDINGS
setup_repo
touch flowyeah.yml
mkdir -p .flowyeah
cat > .flowyeah/review-state-42.md <<'EOF'
# Current State

Type: review
Status: Reviewing
PR/MR: 42
Branch: main
EOF
OUTPUT=$(bash "$SCRIPT_DIR/session-inject.sh" 2>&1)
assert_output_contains "inject review: shows session type" "flowyeah:review session" "$OUTPUT"
assert_output_contains "inject review: shows STATE" "## STATE" "$OUTPUT"
assert_output_contains "inject review: shows PR number" "PR/MR: 42" "$OUTPUT"
assert_output_not_contains "inject review: no MISSION" "## MISSION" "$OUTPUT"
assert_output_not_contains "inject review: no PROGRESS" "## PROGRESS" "$OUTPUT"
assert_output_not_contains "inject review: no FINDINGS" "## FINDINGS" "$OUTPUT"
teardown

# Test: review session injects approved findings summary
setup_repo
touch flowyeah.yml
mkdir -p .flowyeah
cat > .flowyeah/review-state-42.md <<'EOF'
# Current State

Type: review
Status: Interactive Approval
PR/MR: 42
Branch: main
Findings: 5 total, 2 approved
Phase: Interactive Approval
EOF
cat > .flowyeah/review-approved-42.md <<'EOF'
# Approved Findings

## Finding 1
- File: app/models/payment.rb:42
- Label: issue (blocking)
- Body: |
    **issue (blocking):** Race condition

## Finding 3
- File: app/services/webhook.rb:15
- Label: suggestion (non-blocking)
- Body: |
    **suggestion (non-blocking):** Extract method
EOF
OUTPUT=$(bash "$SCRIPT_DIR/session-inject.sh" 2>&1)
assert_output_contains "inject review approved: shows APPROVED section" "## APPROVED FINDINGS" "$OUTPUT"
assert_output_contains "inject review approved: shows finding 1" "## Finding 1" "$OUTPUT"
assert_output_contains "inject review approved: shows file" "app/models/payment.rb:42" "$OUTPUT"
assert_output_contains "inject review approved: shows label" "issue (blocking)" "$OUTPUT"
assert_output_contains "inject review approved: shows finding 3" "## Finding 3" "$OUTPUT"
teardown

# Test: review session injects own-rejections count when file exists
setup_repo
touch flowyeah.yml
mkdir -p .flowyeah
cat > .flowyeah/review-state-42.md <<'EOF'
# Current State

Type: review
Status: Reviewing
PR/MR: 42
Branch: main
Mode: own
EOF
cat > .flowyeah/own-rejections-42.md <<'EOF'
# Previously Rejected Findings (PR #42)

## Rejection 1
- File: app/services/foo.rb:42
- Label: issue
- Subject: Missing null check
- Rejected at: 2026-05-04T15:30:00Z
- Reasoning: |
    DB constraint already enforces this.

## Rejection 2
- File: (general)
- Label: suggestion
- Subject: Extract service object
- Rejected at: 2026-05-04T18:12:00Z
- Reasoning: |
    YAGNI.
EOF
OUTPUT=$(bash "$SCRIPT_DIR/session-inject.sh" 2>&1)
assert_output_contains "inject own-rejections: shows count line" "Previously rejected: 2" "$OUTPUT"
teardown

# Test: review session without own-rejections file shows no count line
setup_repo
touch flowyeah.yml
mkdir -p .flowyeah
cat > .flowyeah/review-state-42.md <<'EOF'
# Current State

Type: review
Status: Reviewing
PR/MR: 42
Branch: main
Mode: own
EOF
OUTPUT=$(bash "$SCRIPT_DIR/session-inject.sh" 2>&1)
assert_output_not_contains "inject no rejections: no count line" "Previously rejected:" "$OUTPUT"
teardown

# Test: own-rejections count is per-PR (other PR's file does not leak)
setup_repo
touch flowyeah.yml
mkdir -p .flowyeah
cat > .flowyeah/review-state-42.md <<'EOF'
# Current State

Type: review
Status: Reviewing
PR/MR: 42
Branch: main
Mode: own
EOF
cat > .flowyeah/own-rejections-77.md <<'EOF'
# Previously Rejected Findings (PR #77)

## Rejection 1
- File: x.rb:1
- Label: issue
- Subject: Foo
- Rejected at: 2026-05-04T00:00:00Z
- Reasoning: |
    Bar.
EOF
OUTPUT=$(bash "$SCRIPT_DIR/session-inject.sh" 2>&1)
assert_output_not_contains "inject other PR rejections: no count line" "Previously rejected:" "$OUTPUT"
teardown

# Test: review session without approved findings shows no APPROVED section
setup_repo
touch flowyeah.yml
mkdir -p .flowyeah
cat > .flowyeah/review-state-42.md <<'EOF'
# Current State

Type: review
Status: Gathering Context
PR/MR: 42
Branch: main
Phase: Gathering Context
EOF
OUTPUT=$(bash "$SCRIPT_DIR/session-inject.sh" 2>&1)
assert_output_not_contains "inject review no approved: no APPROVED section" "## APPROVED FINDINGS" "$OUTPUT"
teardown

# Test: review session coexists with build worktree sessions
setup_repo
touch flowyeah.yml
mkdir -p .flowyeah/worktrees/feat-webhook/.flowyeah
cat > .flowyeah/worktrees/feat-webhook/.flowyeah/state.md <<'EOF'
Type: build
Task: Webhook retry
Step: 4
EOF
cat > .flowyeah/worktrees/feat-webhook/.flowyeah/mission.md <<'EOF'
# Mission
Implement webhook retry.
EOF
mkdir -p .flowyeah
cat > .flowyeah/review-state-42.md <<'EOF'
# Current State

Type: review
Status: Reviewing
PR/MR: 42
Branch: main
EOF
OUTPUT=$(bash "$SCRIPT_DIR/session-inject.sh" 2>&1)
assert_output_contains "inject coexist: shows review session" "flowyeah:review session" "$OUTPUT"
assert_output_contains "inject coexist: shows review PR" "PR/MR: 42" "$OUTPUT"
assert_output_contains "inject coexist: shows build session" "Active session found" "$OUTPUT"
assert_output_contains "inject coexist: shows build state" "Webhook retry" "$OUTPUT"
teardown

# Test: multiple concurrent review sessions both surface (PR-labeled headers)
setup_repo
touch flowyeah.yml
mkdir -p .flowyeah
cat > .flowyeah/review-state-42.md <<'EOF'
# Current State

Type: review
Status: Reviewing
PR/MR: 42
Branch: main
EOF
cat > .flowyeah/review-state-55.md <<'EOF'
# Current State

Type: review
Status: Reviewing
PR/MR: 55
Branch: feat-payment
EOF
OUTPUT=$(bash "$SCRIPT_DIR/session-inject.sh" 2>&1)
assert_output_contains "inject review multi: shows first PR" "PR/MR: 42" "$OUTPUT"
assert_output_contains "inject review multi: shows second PR" "PR/MR: 55" "$OUTPUT"
assert_output_contains "inject review multi: header labels first PR" "flowyeah:review session (PR #42, branch main)" "$OUTPUT"
assert_output_contains "inject review multi: header labels second PR" "flowyeah:review session (PR #55, branch feat-payment)" "$OUTPUT"
teardown

# Test: review session surfaces even when current branch differs (no branch filter)
setup_repo
touch flowyeah.yml
mkdir -p .flowyeah
cat > .flowyeah/review-state-42.md <<'EOF'
# Current State

Type: review
Status: Reviewing
PR/MR: 42
Branch: feat-payment
EOF
OUTPUT=$(bash "$SCRIPT_DIR/session-inject.sh" 2>&1)
assert_output_contains "inject review no branch match: shows session anyway" "flowyeah:review session" "$OUTPUT"
assert_output_contains "inject review no branch match: header shows PR and branch" "(PR #42, branch feat-payment)" "$OUTPUT"
teardown

# Test: approved findings are paired with their state file by PR number
# Both sessions surface, but each state's APPROVED FINDINGS block must come from
# the matching review-approved-{N}.md file — not crossed.
setup_repo
touch flowyeah.yml
mkdir -p .flowyeah
cat > .flowyeah/review-state-42.md <<'EOF'
# Current State

Type: review
Status: Interactive Approval
PR/MR: 42
Branch: main
Phase: Interactive Approval
EOF
cat > .flowyeah/review-approved-42.md <<'EOF'
# Approved Findings

## Finding 1
- File: app/models/payment.rb:42
- Label: issue (blocking)
EOF
cat > .flowyeah/review-state-55.md <<'EOF'
# Current State

Type: review
Status: Reviewing
PR/MR: 55
Branch: feat-other
EOF
cat > .flowyeah/review-approved-55.md <<'EOF'
# Approved Findings

## Finding 9
- File: app/controllers/api.rb:10
- Label: suggestion (non-blocking)
EOF
OUTPUT=$(bash "$SCRIPT_DIR/session-inject.sh" 2>&1)
assert_output_contains "inject review approved pairing: shows PR 42 findings" "app/models/payment.rb:42" "$OUTPUT"
assert_output_contains "inject review approved pairing: shows PR 55 findings" "app/controllers/api.rb:10" "$OUTPUT"
# Pairing: PR 42's findings appear between its header and the next session separator
PR42_BLOCK=$(awk '/flowyeah:review session \(PR #42/,/──────────────────────────────────────────────/' <<< "$OUTPUT")
assert_output_contains "inject review approved pairing: PR 42 block carries its findings" "app/models/payment.rb:42" "$PR42_BLOCK"
assert_output_not_contains "inject review approved pairing: PR 42 block does not carry PR 55 findings" "app/controllers/api.rb:10" "$PR42_BLOCK"
teardown

# Test: detached HEAD still injects review session (no branch filter)
setup_repo
touch flowyeah.yml
git add flowyeah.yml && git commit -q -m "add config"
git checkout -q --detach HEAD
mkdir -p .flowyeah
cat > .flowyeah/review-state-42.md <<'EOF'
# Current State

Type: review
Status: Reviewing
PR/MR: 42
Branch: main
EOF
OUTPUT=$(bash "$SCRIPT_DIR/session-inject.sh" 2>&1)
assert_output_contains "inject review detached HEAD: still shows review session" "flowyeah:review session" "$OUTPUT"
assert_output_contains "inject review detached HEAD: header has PR label" "(PR #42, branch main)" "$OUTPUT"
teardown

# Test: defaults to build when Type is missing
setup_repo
touch flowyeah.yml
mkdir -p .flowyeah
echo "# Current State" > .flowyeah/state.md
OUTPUT=$(bash "$SCRIPT_DIR/session-inject.sh" 2>&1)
assert_output_contains "inject: defaults to build type" "flowyeah:build session" "$OUTPUT"
assert_output_contains "inject: shows MISSION for default type" "## MISSION" "$OUTPUT"
teardown

# Test: findings summary extraction
setup_repo
touch flowyeah.yml
mkdir -p .flowyeah
echo -e "Type: build\n" > .flowyeah/state.md
cat > .flowyeah/findings.md <<'EOF'
# Findings

## Summary
ActiveJob retry_on has a quirk with exponential backoff.

## Details
Long details here...
EOF
OUTPUT=$(bash "$SCRIPT_DIR/session-inject.sh" 2>&1)
assert_output_contains "inject: extracts findings summary" "ActiveJob retry_on" "$OUTPUT"
assert_output_not_contains "inject: excludes findings details" "Long details here" "$OUTPUT"
teardown

# Test: multiple sessions from main checkout
setup_repo
touch flowyeah.yml
mkdir -p .flowyeah/worktrees/feat-webhook/.flowyeah
cat > .flowyeah/worktrees/feat-webhook/.flowyeah/state.md <<'EOF'
Type: build
Task: Webhook retry
Step: 4
EOF
mkdir -p .flowyeah/worktrees/fix-payment/.flowyeah
cat > .flowyeah/worktrees/fix-payment/.flowyeah/state.md <<'EOF'
Type: build
Task: Payment validation
Step: 7b
EOF
OUTPUT=$(bash "$SCRIPT_DIR/session-inject.sh" 2>&1)
assert_output_contains "inject multi: shows count" "2 active sessions" "$OUTPUT"
assert_output_contains "inject multi: lists first session" "feat-webhook" "$OUTPUT"
assert_output_contains "inject multi: lists second session" "fix-payment" "$OUTPUT"
teardown

# Test: task names with special characters (/ and &)
setup_repo
touch flowyeah.yml
mkdir -p .flowyeah/worktrees/feat-api/.flowyeah
cat > .flowyeah/worktrees/feat-api/.flowyeah/state.md <<'EOF'
Type: build
Task: Fix API/webhook & retry handling
Step: 4
EOF
mkdir -p .flowyeah/worktrees/fix-auth/.flowyeah
cat > .flowyeah/worktrees/fix-auth/.flowyeah/state.md <<'EOF'
Type: build
Task: Auth/session cleanup
Step: 2
EOF
OUTPUT=$(bash "$SCRIPT_DIR/session-inject.sh" 2>&1)
assert_output_contains "inject special chars: shows task with /" "API/webhook" "$OUTPUT"
assert_output_contains "inject special chars: shows task with &" "& retry" "$OUTPUT"
teardown

# Test: invalid session type defaults to build
setup_repo
touch flowyeah.yml
mkdir -p .flowyeah
cat > .flowyeah/state.md <<'EOF'
# Current State

Type: garbage
Status: Unknown
EOF
OUTPUT=$(bash "$SCRIPT_DIR/session-inject.sh" 2>&1)
assert_output_contains "inject invalid type: defaults to build" "flowyeah:build session" "$OUTPUT"
assert_output_contains "inject invalid type: shows MISSION" "## MISSION" "$OUTPUT"
teardown

# Test: single session from main checkout
setup_repo
touch flowyeah.yml
mkdir -p .flowyeah/worktrees/feat-webhook/.flowyeah
cat > .flowyeah/worktrees/feat-webhook/.flowyeah/state.md <<'EOF'
Type: build
Task: Webhook retry
Step: 4
EOF
cat > .flowyeah/worktrees/feat-webhook/.flowyeah/mission.md <<'EOF'
# Mission
Implement webhook retry.
EOF
OUTPUT=$(bash "$SCRIPT_DIR/session-inject.sh" 2>&1)
assert_output_contains "inject single remote: finds session" "Active session found" "$OUTPUT"
assert_output_contains "inject single remote: injects state" "## STATE" "$OUTPUT"
teardown

# Test: inject works from inside a real git worktree
setup_repo
touch flowyeah.yml
git add flowyeah.yml && git commit -q -m "add config"
git worktree add -q wt-feat -b feat/test
cd wt-feat
mkdir -p .flowyeah
cat > .flowyeah/state.md <<'EOF'
# Current State

Type: build
Status: Implementing
Task: Feature from worktree
EOF
OUTPUT=$(bash "$SCRIPT_DIR/session-inject.sh" 2>&1)
assert_output_contains "inject worktree: shows build session" "flowyeah:build session" "$OUTPUT"
assert_output_contains "inject worktree: shows task" "Feature from worktree" "$OUTPUT"
cd "$WORKDIR"
git worktree remove wt-feat 2>/dev/null || true
teardown

# ── process_skills injection tests ─────────────────────

echo ""
echo "=== session-inject.sh (process_skills) ==="

# Test: no process_skills → no PROCESS SKILLS section
setup_repo
cat > flowyeah.yml <<'EOF'
testing:
  command: echo test
implementation:
  brainstorm: auto
EOF
mkdir -p .flowyeah
echo -e "Type: build\nStatus: Implementing\nStep: 4" > .flowyeah/state.md
OUTPUT=$(bash "$SCRIPT_DIR/session-inject.sh" 2>&1)
assert_output_not_contains "inject: no PROCESS SKILLS without config" "## PROCESS SKILLS" "$OUTPUT"
teardown

# Test: process_skills configured → PROCESS SKILLS section with skills listed
setup_repo
cat > flowyeah.yml <<'EOF'
testing:
  command: echo test
implementation:
  brainstorm: always
  process_skills:
    brainstorming: superpowers:brainstorming
    planning: superpowers:writing-plans
    tdd: superpowers:test-driven-development
    debugging: superpowers:systematic-debugging
EOF
mkdir -p .flowyeah
echo -e "Type: build\nStatus: Implementing\nStep: 4" > .flowyeah/state.md
OUTPUT=$(bash "$SCRIPT_DIR/session-inject.sh" 2>&1)
assert_output_contains "inject: shows PROCESS SKILLS section" "## PROCESS SKILLS" "$OUTPUT"
assert_output_contains "inject: shows brainstorming skill" "superpowers:brainstorming" "$OUTPUT"
assert_output_contains "inject: shows planning skill" "superpowers:writing-plans" "$OUTPUT"
assert_output_contains "inject: shows tdd skill" "superpowers:test-driven-development" "$OUTPUT"
assert_output_contains "inject: shows debugging skill" "superpowers:systematic-debugging" "$OUTPUT"
teardown

# Test: partial process_skills → only configured phases listed
setup_repo
cat > flowyeah.yml <<'EOF'
testing:
  command: echo test
implementation:
  process_skills:
    tdd: superpowers:test-driven-development
    debugging: superpowers:systematic-debugging
EOF
mkdir -p .flowyeah
echo -e "Type: build\nStatus: Implementing\nStep: 4" > .flowyeah/state.md
OUTPUT=$(bash "$SCRIPT_DIR/session-inject.sh" 2>&1)
assert_output_contains "inject partial: shows PROCESS SKILLS" "## PROCESS SKILLS" "$OUTPUT"
assert_output_contains "inject partial: shows tdd skill" "superpowers:test-driven-development" "$OUTPUT"
assert_output_contains "inject partial: shows debugging skill" "superpowers:systematic-debugging" "$OUTPUT"
assert_output_not_contains "inject partial: no brainstorming" "brainstorming" "$OUTPUT"
assert_output_not_contains "inject partial: no planning" "planning" "$OUTPUT"
teardown

# Test: quoted values → quotes stripped from skill name
setup_repo
cat > flowyeah.yml <<'EOF'
testing:
  command: echo test
implementation:
  process_skills:
    tdd: "superpowers:test-driven-development"
    debugging: 'superpowers:systematic-debugging'
EOF
mkdir -p .flowyeah
echo -e "Type: build\nStatus: Implementing\nStep: 4" > .flowyeah/state.md
OUTPUT=$(bash "$SCRIPT_DIR/session-inject.sh" 2>&1)
assert_output_contains "inject quoted: shows tdd skill without quotes" "superpowers:test-driven-development" "$OUTPUT"
assert_output_contains "inject quoted: shows debugging skill without quotes" "superpowers:systematic-debugging" "$OUTPUT"
assert_output_not_contains "inject quoted: no double quotes in output" '"superpowers' "$OUTPUT"
assert_output_not_contains "inject quoted: no single quotes in output" "'superpowers" "$OUTPUT"
teardown

# Test: inline comments → comment stripped from skill name
setup_repo
cat > flowyeah.yml <<'EOF'
testing:
  command: echo test
implementation:
  process_skills:
    tdd: superpowers:test-driven-development  # TDD skill
    debugging: superpowers:systematic-debugging # debug
EOF
mkdir -p .flowyeah
echo -e "Type: build\nStatus: Implementing\nStep: 4" > .flowyeah/state.md
OUTPUT=$(bash "$SCRIPT_DIR/session-inject.sh" 2>&1)
assert_output_contains "inject comments: shows tdd skill" "superpowers:test-driven-development" "$OUTPUT"
assert_output_not_contains "inject comments: no inline comment in tdd" "# TDD" "$OUTPUT"
assert_output_not_contains "inject comments: no inline comment in debugging" "# debug" "$OUTPUT"
teardown

# Test: null/empty values → phase not listed
setup_repo
cat > flowyeah.yml <<'EOF'
testing:
  command: echo test
implementation:
  process_skills:
    brainstorming: null
    planning:
    tdd: superpowers:test-driven-development
    debugging: ~
EOF
mkdir -p .flowyeah
echo -e "Type: build\nStatus: Implementing\nStep: 4" > .flowyeah/state.md
OUTPUT=$(bash "$SCRIPT_DIR/session-inject.sh" 2>&1)
assert_output_contains "inject null: shows tdd skill" "superpowers:test-driven-development" "$OUTPUT"
assert_output_not_contains "inject null: no brainstorming (null)" "brainstorming" "$OUTPUT"
assert_output_not_contains "inject null: no planning (empty)" "planning" "$OUTPUT"
assert_output_not_contains "inject null: no debugging (tilde)" "debugging" "$OUTPUT"
teardown

# ── pipeline reminder injection tests ────────────────

echo ""
echo "=== session-inject.sh (pipeline reminder) ==="

# Test: unchecked pipeline items appear in REMAINING PIPELINE STEPS section
setup_repo
touch flowyeah.yml
mkdir -p .flowyeah
echo -e "Type: build\nStatus: Implementing\nStep: 7b" > .flowyeah/state.md
cat > .flowyeah/progress.md <<'EOF'
# Progress

## Items
- [x] Implement feature

## Pipeline
- [x] Commit (5)
- [x] Test (6)
- [x] Implementation approval (6b)
- [x] Rebase + push (6c)
- [ ] Issue linkage (6d)
- [ ] Create PR/MR (7)
- [ ] PR hooks (7a)
- [ ] CI + code review (7b)
- [ ] Merge decision (7c)
- [ ] After-merge hooks (8)
- [ ] Mark task done (9)
- [ ] Cleanup worktree (10)
EOF
OUTPUT=$(bash "$SCRIPT_DIR/session-inject.sh" 2>&1)
assert_output_contains "pipeline reminder: shows section header" "REMAINING PIPELINE STEPS" "$OUTPUT"
# Extract only the REMAINING section to avoid false positives from progress.md dump
REMAINING=$(echo "$OUTPUT" | sed -n '/REMAINING PIPELINE STEPS/,$ p')
assert_output_contains "pipeline reminder: remaining has issue linkage" "Issue linkage (6d)" "$REMAINING"
assert_output_contains "pipeline reminder: remaining has after-merge hooks" "After-merge hooks (8)" "$REMAINING"
assert_output_contains "pipeline reminder: remaining has cleanup" "Cleanup worktree (10)" "$REMAINING"
# Checked items must NOT appear in the REMAINING section
assert_output_not_contains "pipeline reminder: remaining excludes checked commit" "Commit (5)" "$REMAINING"
assert_output_not_contains "pipeline reminder: remaining excludes checked test" "Test (6)" "$REMAINING"
teardown

# Test: all pipeline items checked → no REMAINING section
setup_repo
touch flowyeah.yml
mkdir -p .flowyeah
echo -e "Type: build\nStatus: Complete\nStep: 10" > .flowyeah/state.md
cat > .flowyeah/progress.md <<'EOF'
# Progress

## Items
- [x] Implement feature

## Pipeline
- [x] Commit (5)
- [x] Test (6)
- [x] Implementation approval (6b)
- [x] Rebase + push (6c)
- [x] Issue linkage (6d)
- [x] Create PR/MR (7)
- [x] PR hooks (7a)
- [x] CI + code review (7b)
- [x] Merge decision (7c)
- [x] After-merge hooks (8)
- [x] Mark task done (9)
- [x] Cleanup worktree (10)
EOF
OUTPUT=$(bash "$SCRIPT_DIR/session-inject.sh" 2>&1)
assert_output_not_contains "pipeline all done: no REMAINING section" "REMAINING PIPELINE STEPS" "$OUTPUT"
teardown

# Test: no Pipeline section in progress.md → no REMAINING section
setup_repo
touch flowyeah.yml
mkdir -p .flowyeah
echo -e "Type: build\nStatus: Implementing\nStep: 4" > .flowyeah/state.md
cat > .flowyeah/progress.md <<'EOF'
# Progress

## Items
- [x] Design
- [ ] Implement
EOF
OUTPUT=$(bash "$SCRIPT_DIR/session-inject.sh" 2>&1)
assert_output_not_contains "pipeline no section: no REMAINING section" "REMAINING PIPELINE STEPS" "$OUTPUT"
teardown

# Test: REMAINING section appears AFTER the closing separator (last in output)
setup_repo
touch flowyeah.yml
mkdir -p .flowyeah
echo -e "Type: build\nStatus: Implementing\nStep: 7" > .flowyeah/state.md
cat > .flowyeah/progress.md <<'EOF'
# Progress

## Pipeline
- [x] Commit (5)
- [ ] Test (6)
- [ ] Create PR/MR (7)
EOF
OUTPUT=$(bash "$SCRIPT_DIR/session-inject.sh" 2>&1)
# The REMAINING section should come after the last separator line
AFTER_LAST_SEP=$(echo "$OUTPUT" | tac | sed '/──────────────────────────────────────────────/q' | tac)
assert_output_contains "pipeline position: REMAINING after separator" "REMAINING PIPELINE STEPS" "$AFTER_LAST_SEP"
teardown

# Test: no progress.md file → no REMAINING section
setup_repo
touch flowyeah.yml
mkdir -p .flowyeah
echo -e "Type: build\nStatus: Implementing\nStep: 4" > .flowyeah/state.md
OUTPUT=$(bash "$SCRIPT_DIR/session-inject.sh" 2>&1)
assert_output_not_contains "pipeline no file: no REMAINING section" "REMAINING PIPELINE STEPS" "$OUTPUT"
teardown

# Test: pipeline reminder works from main checkout scanning worktree
setup_repo
touch flowyeah.yml
mkdir -p .flowyeah/worktrees/feat-webhook/.flowyeah
cat > .flowyeah/worktrees/feat-webhook/.flowyeah/state.md <<'EOF'
Type: build
Task: Webhook retry
Step: 8
EOF
cat > .flowyeah/worktrees/feat-webhook/.flowyeah/mission.md <<'EOF'
# Mission
Implement webhook retry.
EOF
cat > .flowyeah/worktrees/feat-webhook/.flowyeah/progress.md <<'EOF'
# Progress

## Pipeline
- [x] Commit (5)
- [x] Test (6)
- [x] Rebase + push (6c)
- [x] Create PR/MR (7)
- [x] CI + code review (7b)
- [x] Merge decision (7c)
- [ ] After-merge hooks (8)
- [ ] Mark task done (9)
- [ ] Cleanup worktree (10)
EOF
OUTPUT=$(bash "$SCRIPT_DIR/session-inject.sh" 2>&1)
assert_output_contains "pipeline worktree: shows REMAINING section" "REMAINING PIPELINE STEPS" "$OUTPUT"
REMAINING=$(echo "$OUTPUT" | sed -n '/REMAINING PIPELINE STEPS/,$ p')
assert_output_contains "pipeline worktree: remaining has after-merge hooks" "After-merge hooks (8)" "$REMAINING"
assert_output_contains "pipeline worktree: remaining has mark task done" "Mark task done (9)" "$REMAINING"
teardown

# ── respond session tests ─────────────────────────────

echo ""
echo "=== session-inject.sh (respond) ==="

# Test: respond session injects state
setup_repo
touch flowyeah.yml
mkdir -p .flowyeah
cat > .flowyeah/respond-state-55.md <<'EOF'
# Current State

Type: respond
Status: Responding
PR/MR: 55
Branch: feat-payment
Platform: github
Comments: 8 total
Phase: Interactive Triage
EOF
OUTPUT=$(bash "$SCRIPT_DIR/session-inject.sh" 2>&1)
assert_output_contains "inject respond: shows session type" "flowyeah:respond session" "$OUTPUT"
assert_output_contains "inject respond: shows STATE" "## STATE" "$OUTPUT"
assert_output_contains "inject respond: shows PR number" "PR/MR: 55" "$OUTPUT"
assert_output_not_contains "inject respond: no MISSION" "## MISSION" "$OUTPUT"
assert_output_not_contains "inject respond: no PROGRESS" "## PROGRESS" "$OUTPUT"
assert_output_not_contains "inject respond: no FINDINGS" "## FINDINGS" "$OUTPUT"
teardown

# Test: respond session injects decisions summary
setup_repo
touch flowyeah.yml
mkdir -p .flowyeah
cat > .flowyeah/respond-state-55.md <<'EOF'
# Current State

Type: respond
Status: Responding
PR/MR: 55
Phase: Implementing
EOF
cat > .flowyeah/respond-decisions-55.md <<'EOF'
# Triage Decisions

## Comment 1
- Thread: abc123
- File: app/models/payment.rb:42
- Action: implement
- Note: Add null check

## Comment 2
- Thread: def456
- File: (general)
- Action: reject
- Reply: YAGNI
EOF
OUTPUT=$(bash "$SCRIPT_DIR/session-inject.sh" 2>&1)
assert_output_contains "inject respond decisions: shows DECISIONS section" "## TRIAGE DECISIONS" "$OUTPUT"
assert_output_contains "inject respond decisions: shows comment 1" "## Comment 1" "$OUTPUT"
assert_output_contains "inject respond decisions: shows file" "app/models/payment.rb:42" "$OUTPUT"
assert_output_contains "inject respond decisions: shows action" "Action: implement" "$OUTPUT"
teardown

# Test: respond session without decisions shows no DECISIONS section
setup_repo
touch flowyeah.yml
mkdir -p .flowyeah
cat > .flowyeah/respond-state-55.md <<'EOF'
# Current State

Type: respond
Status: Responding
PR/MR: 55
Phase: Fetching Comments
EOF
OUTPUT=$(bash "$SCRIPT_DIR/session-inject.sh" 2>&1)
assert_output_not_contains "inject respond no decisions: no DECISIONS section" "## TRIAGE DECISIONS" "$OUTPUT"
teardown

# Test: respond session injects --own-mode finding decisions
setup_repo
touch flowyeah.yml
mkdir -p .flowyeah
cat > .flowyeah/respond-state-55.md <<'EOF'
# Current State

Type: respond
Status: Responding
PR/MR: 55
Phase: Implementing
EOF
cat > .flowyeah/respond-decisions-55.md <<'EOF'
# Triage Decisions

## Finding 1
- Thread: own-55-1
- File: app/models/payment.rb:42
- Action: implement
EOF
OUTPUT=$(bash "$SCRIPT_DIR/session-inject.sh" 2>&1)
assert_output_contains "inject respond finding: shows DECISIONS section" "## TRIAGE DECISIONS" "$OUTPUT"
assert_output_contains "inject respond finding: shows finding 1" "## Finding 1" "$OUTPUT"
assert_output_contains "inject respond finding: shows file" "app/models/payment.rb:42" "$OUTPUT"
teardown

# Test: respond session coexists with build worktree sessions
setup_repo
touch flowyeah.yml
mkdir -p .flowyeah/worktrees/feat-webhook/.flowyeah
cat > .flowyeah/worktrees/feat-webhook/.flowyeah/state.md <<'EOF'
Type: build
Task: Webhook retry
Step: 4
EOF
cat > .flowyeah/worktrees/feat-webhook/.flowyeah/mission.md <<'EOF'
# Mission
Implement webhook retry.
EOF
mkdir -p .flowyeah
cat > .flowyeah/respond-state-77.md <<'EOF'
# Current State

Type: respond
Status: Responding
PR/MR: 77
EOF
OUTPUT=$(bash "$SCRIPT_DIR/session-inject.sh" 2>&1)
assert_output_contains "inject respond coexist: shows respond session" "flowyeah:respond session" "$OUTPUT"
assert_output_contains "inject respond coexist: shows respond PR" "PR/MR: 77" "$OUTPUT"
assert_output_contains "inject respond coexist: shows build session" "Active session found" "$OUTPUT"
teardown

# Test: multiple concurrent respond sessions both surface
setup_repo
touch flowyeah.yml
mkdir -p .flowyeah
cat > .flowyeah/respond-state-55.md <<'EOF'
# Current State

Type: respond
Status: Responding
PR/MR: 55
Branch: feat-payment
Phase: Interactive Triage
EOF
cat > .flowyeah/respond-state-77.md <<'EOF'
# Current State

Type: respond
Status: Responding
PR/MR: 77
Branch: fix-auth
Phase: Fetching Comments
EOF
OUTPUT=$(bash "$SCRIPT_DIR/session-inject.sh" 2>&1)
assert_output_contains "inject respond multi: shows first PR" "PR/MR: 55" "$OUTPUT"
assert_output_contains "inject respond multi: shows second PR" "PR/MR: 77" "$OUTPUT"
assert_output_contains "inject respond multi: shows first branch" "feat-payment" "$OUTPUT"
assert_output_contains "inject respond multi: shows second branch" "fix-auth" "$OUTPUT"
assert_output_contains "inject respond multi: header labels first PR" "flowyeah:respond session (PR #55, branch feat-payment)" "$OUTPUT"
assert_output_contains "inject respond multi: header labels second PR" "flowyeah:respond session (PR #77, branch fix-auth)" "$OUTPUT"
teardown

# Test: session-remind.sh outputs reminder for respond session
setup_repo
touch flowyeah.yml
mkdir -p .flowyeah
echo -e "# Current State\nPR/MR: 55" > .flowyeah/respond-state-55.md
OUTPUT=$(bash "$SCRIPT_DIR/session-remind.sh" 2>&1)
assert_output_contains "remind: outputs reminder with respond session" "Update respond-state-55.md" "$OUTPUT"
teardown

# Test: session-remind.sh reaches model context via additionalContext JSON
# (PostToolUse stdout with exit 0 is transcript-only)
setup_repo
touch flowyeah.yml
mkdir -p .flowyeah
echo -e "# Current State\nPR/MR: 55" > .flowyeah/respond-state-55.md
OUTPUT=$(bash "$SCRIPT_DIR/session-remind.sh" 2>&1)
assert_output_contains "remind: emits hookSpecificOutput envelope" '"hookSpecificOutput"' "$OUTPUT"
assert_output_contains "remind: emits additionalContext field" '"additionalContext"' "$OUTPUT"
teardown

# Test: session-remind.sh names review AND respond sessions together
setup_repo
touch flowyeah.yml
mkdir -p .flowyeah
echo -e "# Current State\nPR/MR: 42" > .flowyeah/review-state-42.md
echo -e "# Current State\nPR/MR: 55" > .flowyeah/respond-state-55.md
echo -e "# Current State\nPR/MR: 43" > .flowyeah/review-state-43.md
OUTPUT=$(bash "$SCRIPT_DIR/session-remind.sh" 2>&1)
assert_output_contains "remind coexist: names first review file" "review-state-42.md" "$OUTPUT"
assert_output_contains "remind coexist: names second review file" "review-state-43.md" "$OUTPUT"
assert_output_contains "remind coexist: names respond file" "respond-state-55.md" "$OUTPUT"
teardown

# Test: session-inject.sh stays quiet on a rejections file with zero rejections
setup_repo
touch flowyeah.yml
mkdir -p .flowyeah
echo -e "# Current State\nPR/MR: 42\nBranch: main" > .flowyeah/review-state-42.md
echo "# Previously Rejected Findings (PR #42)" > .flowyeah/own-rejections-42.md
OUTPUT=$(bash "$SCRIPT_DIR/session-inject.sh" 2>&1)
assert_output_not_contains "inject: no shell error on zero-rejection file" "integer expected" "$OUTPUT"
assert_output_not_contains "inject: no rejected-count line for empty ledger" "Previously rejected" "$OUTPUT"
teardown

# ── tree-guard.sh tests ────────────────────────────────

echo ""
echo "=== tree-guard.sh ==="

if ! command -v jq >/dev/null 2>&1; then
    TOTAL=$((TOTAL + 1))
    FAIL=$((FAIL + 1))
    echo "FAIL: jq is required for the tree-guard tests — install jq and re-run"
else
    GUARD="$SCRIPT_DIR/tree-guard.sh"
    GUARD_RC=0
    GUARD_OUT=""

    # Invoke the hook with a synthetic Bash tool payload. Sets GUARD_RC and
    # GUARD_OUT (combined stdout+stderr). Tolerates non-zero exits under set -e.
    guard_run() {
        local payload
        payload=$(jq -n --arg c "$1" --arg w "$2" \
            '{tool_name:"Bash", tool_input:{command:$c}, cwd:$w}')
        GUARD_RC=0
        GUARD_OUT=$(printf '%s' "$payload" | bash "$GUARD" 2>&1) || GUARD_RC=$?
    }

    # ── Active review session in primary checkout: mutating commands blocked ──

    setup_repo
    touch flowyeah.yml
    mkdir -p .flowyeah
    cat > .flowyeah/review-state-42.md <<'EOF'
Type: review
PR/MR: 42
Branch: main
Phase: Running Agents
Worktree: none
EOF

    guard_run "git checkout pr-branch -- ." "$WORKDIR"
    assert_exit_eq "guard: blocks git checkout in primary" 2 "$GUARD_RC"
    assert_output_contains "guard: block message names PR" "PR/MR #42" "$GUARD_OUT"
    assert_output_contains "guard: block message names branch" "branch: main" "$GUARD_OUT"
    assert_output_contains "guard: block message points at finalize" "/flowyeah:review finalize 42" "$GUARD_OUT"

    guard_run "git reset --hard HEAD~1" "$WORKDIR"
    assert_exit_eq "guard: blocks git reset --hard" 2 "$GUARD_RC"

    guard_run "cd somewhere && git switch other" "$WORKDIR"
    assert_exit_eq "guard: blocks chained git switch" 2 "$GUARD_RC"

    guard_run "git stash" "$WORKDIR"
    assert_exit_eq "guard: blocks git stash" 2 "$GUARD_RC"

    guard_run "git restore ." "$WORKDIR"
    assert_exit_eq "guard: blocks git restore" 2 "$GUARD_RC"

    guard_run "git apply patch.diff" "$WORKDIR"
    assert_exit_eq "guard: blocks git apply" 2 "$GUARD_RC"

    guard_run "git rebase main" "$WORKDIR"
    assert_exit_eq "guard: blocks git rebase" 2 "$GUARD_RC"

    guard_run "git pull" "$WORKDIR"
    assert_exit_eq "guard: blocks git pull" 2 "$GUARD_RC"

    guard_run "git clean -fd" "$WORKDIR"
    assert_exit_eq "guard: blocks git clean" 2 "$GUARD_RC"

    # ── Active review session: read-only and unrelated commands allowed ──

    guard_run "git fetch origin" "$WORKDIR"
    assert_exit_eq "guard: allows git fetch" 0 "$GUARD_RC"

    guard_run "git show abc123:path/file.rb" "$WORKDIR"
    assert_exit_eq "guard: allows git show" 0 "$GUARD_RC"

    guard_run "git blame abc123 -- path/file.rb" "$WORKDIR"
    assert_exit_eq "guard: allows git blame" 0 "$GUARD_RC"

    guard_run "gh pr diff 42" "$WORKDIR"
    assert_exit_eq "guard: allows gh pr diff" 0 "$GUARD_RC"

    guard_run "ls -la" "$WORKDIR"
    assert_exit_eq "guard: allows ls" 0 "$GUARD_RC"

    guard_run "git log --oneline -10 path/file.rb" "$WORKDIR"
    assert_exit_eq "guard: allows git log" 0 "$GUARD_RC"

    # False-positive guard: 'gitlab-checkout' is not 'git checkout'.
    guard_run "echo gitlab-checkout-notify" "$WORKDIR"
    assert_exit_eq "guard: allows non-git-verb substring" 0 "$GUARD_RC"

    # ── Allowed: cwd inside the review worktree (mutation is sanctioned there) ──

    git -C "$WORKDIR" config --local user.email test@example.com
    git -C "$WORKDIR" config --local user.name test
    git -C "$WORKDIR" worktree add -q --detach .flowyeah/review-worktrees/42

    guard_run "git checkout other -- ." "$WORKDIR/.flowyeah/review-worktrees/42"
    assert_exit_eq "guard: allows mutation inside review worktree" 0 "$GUARD_RC"

    guard_run "git reset --hard" "$WORKDIR/.flowyeah/review-worktrees/42"
    assert_exit_eq "guard: allows reset inside review worktree" 0 "$GUARD_RC"

    # ── Allowed: cwd inside a build worktree (review hook does not interfere) ──

    git -C "$WORKDIR" worktree add -q --detach .flowyeah/worktrees/build-thing

    guard_run "git checkout other -- ." "$WORKDIR/.flowyeah/worktrees/build-thing"
    assert_exit_eq "guard: allows mutation inside build worktree" 0 "$GUARD_RC"

    git -C "$WORKDIR" worktree remove --force .flowyeah/review-worktrees/42 2>/dev/null || true
    git -C "$WORKDIR" worktree remove --force .flowyeah/worktrees/build-thing 2>/dev/null || true
    teardown

    # ── Allowed: review session exists but for a different branch ──

    setup_repo
    touch flowyeah.yml
    mkdir -p .flowyeah
    cat > .flowyeah/review-state-99.md <<'EOF'
Type: review
PR/MR: 99
Branch: feat-other
Phase: Running Agents
EOF
    guard_run "git reset --hard" "$WORKDIR"
    assert_exit_eq "guard: allows when branch does not match" 0 "$GUARD_RC"
    teardown

    # ── Allowed: no review session at all ──

    setup_repo
    touch flowyeah.yml
    guard_run "git reset --hard" "$WORKDIR"
    assert_exit_eq "guard: allows when no review session exists" 0 "$GUARD_RC"
    teardown

    # ── Allowed: not a flowyeah project ──

    setup_repo
    guard_run "git reset --hard" "$WORKDIR"
    assert_exit_eq "guard: allows in non-flowyeah project" 0 "$GUARD_RC"
    teardown

    # ── Allowed: non-Bash tool calls ──

    setup_repo
    touch flowyeah.yml
    mkdir -p .flowyeah
    cat > .flowyeah/review-state-42.md <<'EOF'
Type: review
PR/MR: 42
Branch: main
EOF
    NON_BASH_PAYLOAD=$(jq -n --arg w "$WORKDIR" \
        '{tool_name:"Read", tool_input:{file_path:"foo"}, cwd:$w}')
    NON_BASH_RC=0
    NON_BASH_OUT=$(printf '%s' "$NON_BASH_PAYLOAD" | bash "$GUARD" 2>&1) || NON_BASH_RC=$?
    assert_exit_eq "guard: ignores non-Bash tool calls" 0 "$NON_BASH_RC"
    assert_empty "guard: silent on non-Bash tool calls" "$NON_BASH_OUT"

    # Empty payload → must allow, not crash.
    EMPTY_RC=0
    EMPTY_OUT=$(printf '' | bash "$GUARD" 2>&1) || EMPTY_RC=$?
    assert_exit_eq "guard: allows on empty stdin" 0 "$EMPTY_RC"

    # Malformed JSON → must allow, not crash.
    GARBAGE_RC=0
    GARBAGE_OUT=$(printf 'not json' | bash "$GUARD" 2>&1) || GARBAGE_RC=$?
    assert_exit_eq "guard: allows on malformed JSON" 0 "$GARBAGE_RC"

    teardown

    # ── Active respond session: same blocking rules as review ──

    setup_repo
    touch flowyeah.yml
    mkdir -p .flowyeah
    cat > .flowyeah/respond-state-77.md <<'EOF'
Type: respond
PR/MR: 77
Branch: main
Phase: Implementing
Worktree: none
EOF

    guard_run "git checkout other -- ." "$WORKDIR"
    assert_exit_eq "guard respond: blocks git checkout in primary" 2 "$GUARD_RC"
    assert_output_contains "guard respond: block message names session type" "respond session" "$GUARD_OUT"
    assert_output_contains "guard respond: block message names PR" "PR/MR #77" "$GUARD_OUT"
    assert_output_contains "guard respond: block message points at worktree" ".flowyeah/worktrees/main/" "$GUARD_OUT"
    assert_output_contains "guard respond: block message has abort hint" "respond-state-77.md" "$GUARD_OUT"

    guard_run "git reset --hard" "$WORKDIR"
    assert_exit_eq "guard respond: blocks git reset" 2 "$GUARD_RC"

    guard_run "git stash" "$WORKDIR"
    assert_exit_eq "guard respond: blocks git stash" 2 "$GUARD_RC"

    # Read-only commands still pass during respond.
    guard_run "git fetch origin" "$WORKDIR"
    assert_exit_eq "guard respond: allows git fetch" 0 "$GUARD_RC"

    guard_run "gh api repos/foo/bar/pulls/77/comments" "$WORKDIR"
    assert_exit_eq "guard respond: allows gh api" 0 "$GUARD_RC"

    # Inside the respond worktree (built by step 5), mutations are sanctioned.
    git -C "$WORKDIR" config --local user.email test@example.com
    git -C "$WORKDIR" config --local user.name test
    git -C "$WORKDIR" worktree add -q --detach .flowyeah/worktrees/main

    guard_run "git checkout other -- ." "$WORKDIR/.flowyeah/worktrees/main"
    assert_exit_eq "guard respond: allows mutation inside respond worktree" 0 "$GUARD_RC"

    git -C "$WORKDIR" worktree remove --force .flowyeah/worktrees/main 2>/dev/null || true
    teardown

    # ── Respond session on a slash branch: message points at flattened dir ──

    setup_repo
    git checkout -q -b feat/5588
    touch flowyeah.yml
    mkdir -p .flowyeah
    cat > .flowyeah/respond-state-88.md <<'EOF'
Type: respond
PR/MR: 88
Branch: feat/5588
Phase: Implementing
Worktree: none
EOF

    guard_run "git reset --hard" "$WORKDIR"
    assert_exit_eq "guard respond: blocks on slash branch" 2 "$GUARD_RC"
    assert_output_contains "guard respond: worktree path flattens slash branch" ".flowyeah/worktrees/feat-5588/" "$GUARD_OUT"
    teardown

    # ── Branch field parsing: whitespace variants still match ──

    setup_repo
    touch flowyeah.yml
    mkdir -p .flowyeah
    printf 'Type: review\nPR/MR: 43\nBranch: main \nPhase: Interactive Approval\n' > .flowyeah/review-state-43.md
    guard_run "git reset --hard" "$WORKDIR"
    assert_exit_eq "guard: blocks despite trailing space in Branch field" 2 "$GUARD_RC"

    printf 'Type: review\nPR/MR: 43\nBranch:main\nPhase: Interactive Approval\n' > .flowyeah/review-state-43.md
    guard_run "git reset --hard" "$WORKDIR"
    assert_exit_eq "guard: blocks despite missing space after Branch:" 2 "$GUARD_RC"
    teardown

    # ── Phase-aware: review phases where the pipeline is inactive do not block ──

    setup_repo
    touch flowyeah.yml
    mkdir -p .flowyeah
    for phase in Fixing Delegated Responded; do
        cat > .flowyeah/review-state-44.md <<EOF
Type: review
PR/MR: 44
Branch: main
Phase: $phase
EOF
        guard_run "git pull origin main" "$WORKDIR"
        assert_exit_eq "guard: review phase $phase does not block" 0 "$GUARD_RC"
    done

    cat > .flowyeah/review-state-44.md <<EOF
Type: review
PR/MR: 44
Branch: main
Phase: Interactive Approval
EOF
    guard_run "git pull origin main" "$WORKDIR"
    assert_exit_eq "guard: active review phase still blocks" 2 "$GUARD_RC"
    teardown

    # ── Bypass hardening: global options, glued separators, missing verbs ──

    setup_repo
    touch flowyeah.yml
    mkdir -p .flowyeah
    cat > .flowyeah/review-state-50.md <<'EOF'
Type: review
PR/MR: 50
Branch: main
Phase: Interactive Approval
EOF

    guard_run "git -C /tmp checkout main" "$WORKDIR"
    assert_exit_eq "guard: blocks git -C form" 2 "$GUARD_RC"

    guard_run "git --git-dir=.git --work-tree=. checkout main" "$WORKDIR"
    assert_exit_eq "guard: blocks --git-dir= form" 2 "$GUARD_RC"

    guard_run "git -c core.pager=cat pull" "$WORKDIR"
    assert_exit_eq "guard: blocks -c key=val form" 2 "$GUARD_RC"

    guard_run "git pull;true" "$WORKDIR"
    assert_exit_eq "guard: blocks verb glued to semicolon" 2 "$GUARD_RC"

    guard_run "git pull|cat" "$WORKDIR"
    assert_exit_eq "guard: blocks verb glued to pipe" 2 "$GUARD_RC"

    guard_run "git stash&&echo done" "$WORKDIR"
    assert_exit_eq "guard: blocks verb glued to ampersand" 2 "$GUARD_RC"

    guard_run "git cherry-pick abc123" "$WORKDIR"
    assert_exit_eq "guard: blocks cherry-pick" 2 "$GUARD_RC"

    guard_run "git revert HEAD" "$WORKDIR"
    assert_exit_eq "guard: blocks revert" 2 "$GUARD_RC"

    guard_run "git rm -r app/" "$WORKDIR"
    assert_exit_eq "guard: blocks git rm" 2 "$GUARD_RC"

    guard_run "git mv a b" "$WORKDIR"
    assert_exit_eq "guard: blocks git mv" 2 "$GUARD_RC"

    # ── False positives: read-only subforms must pass ──

    guard_run "git stash list" "$WORKDIR"
    assert_exit_eq "guard: allows git stash list" 0 "$GUARD_RC"

    guard_run "git stash show -p stash@{0}" "$WORKDIR"
    assert_exit_eq "guard: allows git stash show" 0 "$GUARD_RC"

    guard_run "git clean -n" "$WORKDIR"
    assert_exit_eq "guard: allows git clean dry-run" 0 "$GUARD_RC"

    guard_run "git clean -fdn" "$WORKDIR"
    assert_exit_eq "guard: allows git clean combined dry-run flags" 0 "$GUARD_RC"

    guard_run "git clean -fd" "$WORKDIR"
    assert_exit_eq "guard: still blocks real git clean" 2 "$GUARD_RC"

    guard_run "git diff main...feature" "$WORKDIR"
    assert_exit_eq "guard: allows git diff" 0 "$GUARD_RC"

    guard_run "git log --oneline -5" "$WORKDIR"
    assert_exit_eq "guard: allows git log with long option" 0 "$GUARD_RC"

    # Detached HEAD: no branch to match — allowed by design (mutations from
    # detached HEAD touch no session's branch; a checkout onto the session
    # branch re-arms the guard for subsequent commands).
    git checkout -q --detach
    guard_run "git reset --hard" "$WORKDIR"
    assert_exit_eq "guard: allows on detached HEAD (documented design)" 0 "$GUARD_RC"
    git checkout -q main

    teardown

    # ── Respond session for a different branch is ignored ──

    setup_repo
    touch flowyeah.yml
    mkdir -p .flowyeah
    cat > .flowyeah/respond-state-77.md <<'EOF'
Type: respond
PR/MR: 77
Branch: feat-other
Phase: Implementing
EOF
    guard_run "git reset --hard" "$WORKDIR"
    assert_exit_eq "guard respond: allows when branch does not match" 0 "$GUARD_RC"
    teardown

    # ── Both review and respond active for the same branch: review wins (consistent message) ──

    setup_repo
    touch flowyeah.yml
    mkdir -p .flowyeah
    cat > .flowyeah/review-state-42.md <<'EOF'
Type: review
PR/MR: 42
Branch: main
Phase: Running Agents
EOF
    cat > .flowyeah/respond-state-42.md <<'EOF'
Type: respond
PR/MR: 42
Branch: main
Phase: Implementing
EOF
    guard_run "git checkout other -- ." "$WORKDIR"
    assert_exit_eq "guard both: blocks (review takes precedence)" 2 "$GUARD_RC"
    assert_output_contains "guard both: message names review session" "review session" "$GUARD_OUT"
    assert_output_contains "guard both: message points at review worktree path" ".flowyeah/review-worktrees/42/" "$GUARD_OUT"
    teardown

    # ── Active build session: primary checkout is NOT blocked ──
    #
    # Build pipelines run isolated inside .flowyeah/worktrees/<name>/, on a
    # branch git itself prevents the primary from sharing. The primary checkout
    # is therefore mechanically isolated from the build, and tree-guard does not
    # interfere with operations from the primary while a build session exists.
    # This used to block deploys and unrelated work on stable branches whenever
    # any build session was open in any worktree.

    setup_repo
    touch flowyeah.yml
    mkdir -p .flowyeah/worktrees/feat-5588/.flowyeah
    cat > .flowyeah/worktrees/feat-5588/.flowyeah/state.md <<'EOF'
# Current State

Type: build
Status: Implementing
Step: 4
Task: Webhook retry
Worktree: .flowyeah/worktrees/feat-5588
EOF

    guard_run "git checkout main" "$WORKDIR"
    assert_exit_eq "guard build: allows git checkout in primary on unrelated branch" 0 "$GUARD_RC"

    guard_run "git pull origin develop" "$WORKDIR"
    assert_exit_eq "guard build: allows git pull on unrelated branch" 0 "$GUARD_RC"

    guard_run "git merge develop" "$WORKDIR"
    assert_exit_eq "guard build: allows git merge on unrelated branch" 0 "$GUARD_RC"

    guard_run "git reset --hard" "$WORKDIR"
    assert_exit_eq "guard build: allows git reset" 0 "$GUARD_RC"

    guard_run "git stash" "$WORKDIR"
    assert_exit_eq "guard build: allows git stash" 0 "$GUARD_RC"

    guard_run "git rebase develop" "$WORKDIR"
    assert_exit_eq "guard build: allows git rebase" 0 "$GUARD_RC"

    guard_run "git clean -fd" "$WORKDIR"
    assert_exit_eq "guard build: allows git clean" 0 "$GUARD_RC"

    guard_run "git fetch origin" "$WORKDIR"
    assert_exit_eq "guard build: allows git fetch" 0 "$GUARD_RC"

    guard_run "git log --oneline -10" "$WORKDIR"
    assert_exit_eq "guard build: allows git log" 0 "$GUARD_RC"

    teardown

    # ── Multiple build sessions active: still does not block primary ──

    setup_repo
    touch flowyeah.yml
    mkdir -p .flowyeah/worktrees/feat-A/.flowyeah
    mkdir -p .flowyeah/worktrees/feat-B/.flowyeah
    echo "Type: build" > .flowyeah/worktrees/feat-A/.flowyeah/state.md
    echo "Type: build" > .flowyeah/worktrees/feat-B/.flowyeah/state.md

    guard_run "git checkout other" "$WORKDIR"
    assert_exit_eq "guard build multi: allows" 0 "$GUARD_RC"

    guard_run "git pull origin develop" "$WORKDIR"
    assert_exit_eq "guard build multi: allows git pull" 0 "$GUARD_RC"
    teardown

    # ── Review session blocks even when a build session coexists ──
    # Concurrent build sessions are ignored by tree-guard; the review match on
    # the current branch is what fires here.

    setup_repo
    touch flowyeah.yml
    mkdir -p .flowyeah .flowyeah/worktrees/feat-A/.flowyeah
    cat > .flowyeah/review-state-42.md <<'EOF'
Type: review
PR/MR: 42
Branch: main
Phase: Running Agents
EOF
    echo "Type: build" > .flowyeah/worktrees/feat-A/.flowyeah/state.md

    guard_run "git checkout other -- ." "$WORKDIR"
    assert_exit_eq "guard build+review: blocks via review" 2 "$GUARD_RC"
    assert_output_contains "guard build+review: review session named" "review session" "$GUARD_OUT"
    assert_output_contains "guard build+review: review PR named" "PR/MR #42" "$GUARD_OUT"
    teardown
fi

# ── adapter config-schema tests ─────────────────────────
echo ""
echo "=== adapter config-schema.md ==="

# Every adapter must declare its config schema — an adapter with no config
# keys declares an empty one, so unknown keys under it are still flagged.
# Discovery-based: a future adapter automatically gets this check.
ADAPTERS_DIR="$(cd "$(dirname "$SCRIPT_DIR")/adapters" && pwd)"
for dir in "$ADAPTERS_DIR"/*/; do
    adapter="$(basename "$dir")"
    case "$adapter" in _*) continue ;; esac
    schema="$dir/config-schema.md"
    TOTAL=$((TOTAL + 1))
    if [ -f "$schema" ] && grep -qF "## Keys" "$schema"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $adapter has config-schema.md with ## Keys section"
        echo "  expected file with '## Keys': $schema"
    fi
done

# ── bump-version.sh tests ────────────────────────────────
echo ""
echo "=== bump-version.sh ==="

BUMP="$(cd "$SCRIPT_DIR/../../.." && pwd)/scripts/bump-version.sh"

# Build a scratch repo with the manifest layout bump-version expects.
setup_manifest_repo() {
    setup_repo
    mkdir -p plugins/flowyeah/.claude-plugin .claude-plugin
    printf '{\n  "name": "flowyeah",\n  "version": "%s"\n}\n' "$1" \
        > plugins/flowyeah/.claude-plugin/plugin.json
    printf '{\n  "metadata": {"version": "%s"},\n  "plugins": [{"version": "%s"}]\n}\n' "$2" "$2" \
        > .claude-plugin/marketplace.json
    git add -A && git commit -qm manifests
}

manifest_version() {
    sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$1" | head -1
}

# Normal bump: both files move to the next patch, staged.
setup_manifest_repo 1.0.10 1.0.10
RC=0; OUTPUT=$(bash "$BUMP" 2>&1) || RC=$?
assert_exit_eq "bump: exits zero on normal bump" 0 "$RC"
assert_output_contains "bump: reports old and new version" "1.0.10 -> 1.0.11" "$OUTPUT"
TOTAL=$((TOTAL + 1))
if [ "$(manifest_version plugins/flowyeah/.claude-plugin/plugin.json)" = "1.0.11" ] && \
   [ "$(grep -c '"version": "1.0.11"' .claude-plugin/marketplace.json)" -eq 2 ]; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
    echo "FAIL: bump: rewrites plugin.json once and marketplace.json twice"
fi
teardown

# Retry after a failed commit: second run without a commit must not re-bump.
setup_manifest_repo 1.0.10 1.0.10
bash "$BUMP" >/dev/null 2>&1
RC=0; OUTPUT=$(bash "$BUMP" 2>&1) || RC=$?
assert_exit_eq "bump: retry exits zero" 0 "$RC"
TOTAL=$((TOTAL + 1))
if [ "$(manifest_version plugins/flowyeah/.claude-plugin/plugin.json)" = "1.0.11" ]; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
    echo "FAIL: bump: second run without commit does not double-bump"
    echo "  got: $(manifest_version plugins/flowyeah/.claude-plugin/plugin.json)"
fi
teardown

# Drift: marketplace version differs from plugin version — refuse loudly.
setup_manifest_repo 1.0.10 9.9.9
RC=0; OUTPUT=$(bash "$BUMP" 2>&1) || RC=$?
TOTAL=$((TOTAL + 1))
if [ "$RC" -ne 0 ]; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
    echo "FAIL: bump: exits non-zero on manifest drift"
fi
assert_output_contains "bump: drift message names both versions" "9.9.9" "$OUTPUT"
teardown

# Non-numeric patch segment: refuse instead of aborting mid-write.
setup_manifest_repo 1.0.3-beta 1.0.3-beta
RC=0; OUTPUT=$(bash "$BUMP" 2>&1) || RC=$?
TOTAL=$((TOTAL + 1))
if [ "$RC" -ne 0 ]; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
    echo "FAIL: bump: exits non-zero on non-numeric patch"
fi
teardown

# ── Results ──────────────────────────────────────────────

echo ""
echo "════════════════════════════════════════"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo "════════════════════════════════════════"

[ "$FAIL" -eq 0 ] || exit 1
