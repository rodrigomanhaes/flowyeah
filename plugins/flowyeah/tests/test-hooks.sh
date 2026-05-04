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
    TMPDIR=$(mktemp -d)
    cd "$TMPDIR"
    git init -q -b main
    git commit --allow-empty -m "init" -q
}

teardown() {
    cd /
    rm -rf "$TMPDIR"
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

# ── session-remind.sh tests ─────────────────────────────

echo "=== session-remind.sh ==="

# Test: silent when no flowyeah session
setup_repo
OUTPUT=$(bash "$SCRIPT_DIR/session-remind.sh" 2>&1 || true)
assert_empty "remind: silent without session" "$OUTPUT"
teardown

# Test: silent when no git repo
TMPDIR=$(mktemp -d)
cd "$TMPDIR"
OUTPUT=$(bash "$SCRIPT_DIR/session-remind.sh" 2>&1 || true)
assert_empty "remind: silent outside git repo" "$OUTPUT"
cd /; rm -rf "$TMPDIR"

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

# Test: branch match injects correct review (only matching branch)
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
assert_output_contains "inject review branch match: shows matching PR" "PR/MR: 42" "$OUTPUT"
assert_output_not_contains "inject review branch match: hides non-matching PR" "PR/MR: 55" "$OUTPUT"
teardown

# Test: no branch match stays silent for reviews
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
assert_output_not_contains "inject review no match: no review session" "flowyeah:review session" "$OUTPUT"
teardown

# Test: approved findings follow their state file by PR number
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
assert_output_contains "inject review approved match: shows PR 42 findings" "app/models/payment.rb:42" "$OUTPUT"
assert_output_not_contains "inject review approved match: hides PR 55 findings" "app/controllers/api.rb:10" "$OUTPUT"
teardown

# Test: detached HEAD skips review injection
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
assert_output_not_contains "inject review detached HEAD: no review session" "flowyeah:review session" "$OUTPUT"
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
cd "$TMPDIR"
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
teardown

# Test: session-remind.sh outputs reminder for respond session
setup_repo
touch flowyeah.yml
mkdir -p .flowyeah
echo -e "# Current State\nPR/MR: 55" > .flowyeah/respond-state-55.md
OUTPUT=$(bash "$SCRIPT_DIR/session-remind.sh" 2>&1)
assert_output_contains "remind: outputs reminder with respond session" "Update respond-state-55.md" "$OUTPUT"
teardown

# ── Results ──────────────────────────────────────────────

echo ""
echo "════════════════════════════════════════"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo "════════════════════════════════════════"

[ "$FAIL" -eq 0 ] || exit 1
