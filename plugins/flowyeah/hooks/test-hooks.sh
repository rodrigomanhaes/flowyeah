#!/bin/bash
# Tests for flowyeah hooks (session-inject.sh and session-remind.sh).
# Run from anywhere: bash plugins/flowyeah/hooks/test-hooks.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PASS=0
FAIL=0
TOTAL=0

# ── Helpers ──────────────────────────────────────────────

setup_repo() {
    TMPDIR=$(mktemp -d)
    cd "$TMPDIR"
    git init -q
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

# Test: outputs reminder when build session is active
setup_repo
mkdir -p .flowyeah
echo "# Current State" > .flowyeah/state.md
OUTPUT=$(bash "$SCRIPT_DIR/session-remind.sh" 2>&1)
assert_output_contains "remind: outputs reminder with build session" "Update .flowyeah/state.md" "$OUTPUT"
teardown

# Test: outputs reminder when review session is active
setup_repo
mkdir -p .flowyeah
echo "# Current State" > .flowyeah/review-state.md
OUTPUT=$(bash "$SCRIPT_DIR/session-remind.sh" 2>&1)
assert_output_contains "remind: outputs reminder with review session" "Update .flowyeah/review-state.md" "$OUTPUT"
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
cat > .flowyeah/review-state.md <<'EOF'
# Current State

Type: review
Status: Reviewing
PR/MR: 42
EOF
OUTPUT=$(bash "$SCRIPT_DIR/session-inject.sh" 2>&1)
assert_output_contains "inject review: shows session type" "flowyeah:review session" "$OUTPUT"
assert_output_contains "inject review: shows STATE" "## STATE" "$OUTPUT"
assert_output_contains "inject review: shows PR number" "PR/MR: 42" "$OUTPUT"
assert_output_not_contains "inject review: no MISSION" "## MISSION" "$OUTPUT"
assert_output_not_contains "inject review: no PROGRESS" "## PROGRESS" "$OUTPUT"
assert_output_not_contains "inject review: no FINDINGS" "## FINDINGS" "$OUTPUT"
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
cat > .flowyeah/review-state.md <<'EOF'
# Current State

Type: review
Status: Reviewing
PR/MR: 99
EOF
OUTPUT=$(bash "$SCRIPT_DIR/session-inject.sh" 2>&1)
assert_output_contains "inject coexist: shows review session" "flowyeah:review session" "$OUTPUT"
assert_output_contains "inject coexist: shows review PR" "PR/MR: 99" "$OUTPUT"
assert_output_contains "inject coexist: shows build session" "Active session found" "$OUTPUT"
assert_output_contains "inject coexist: shows build state" "Webhook retry" "$OUTPUT"
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

# ── Results ──────────────────────────────────────────────

echo ""
echo "════════════════════════════════════════"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo "════════════════════════════════════════"

[ "$FAIL" -eq 0 ] || exit 1
