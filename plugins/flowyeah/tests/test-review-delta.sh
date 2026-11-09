#!/bin/bash
# Tests for bin/review-delta, the hunks an author changed between two reviewed heads.
# Run from anywhere: bash plugins/flowyeah/tests/test-review-delta.sh

set -uo pipefail

DELTA="$(cd "$(dirname "$0")/../bin" && pwd)/review-delta"
PASS=0
FAIL=0
TOTAL=0

# ── Helpers ──────────────────────────────────────────────

# A bare repo as `origin` and a clone in $ROOT/work, with four 100-line files
# on main. The bare repo serves unadvertised SHAs, as GitHub and GitLab do.
setup_repo() {
    ROOT=$(mktemp -d)
    git init -q --bare -b main "$ROOT/origin.git"
    git -C "$ROOT/origin.git" config uploadpack.allowAnySHA1InWant true
    git clone -q "$ROOT/origin.git" "$ROOT/work" 2>/dev/null
    cd "$ROOT/work"
    git checkout -q -B main
    for f in A B C D; do seq 1 100 | sed "s/^/$f/" > "$f.txt"; done
    git add . && git commit -qm base && git push -q origin main
}

teardown() {
    cd /
    rm -rf "$ROOT"
}

# Replace line "<prefix><n>" in <file> with <text>.
edit_line() {
    sed -i "s/^$2\$/$3/" "$1"
}

commit_push() {
    git commit -qam "$1"
    git push -q -f origin HEAD 2>/dev/null
    git rev-parse HEAD
}

# Round 1 of a PR touching A, B, C and D at line 50. Prints the head.
open_pr() {
    git checkout -q -b pr
    for f in A B C D; do edit_line "$f.txt" "${f}50" "${f}50 pr"; done
    commit_push "pr round 1"
}

# main moves: shifts A's lines, edits B far from the PR hunk, edits a context
# line of C's PR hunk. Leaves the PR branch checked out, rebased onto main.
move_main_and_rebase() {
    git checkout -q main
    sed -i '1i A0 main' A.txt
    edit_line B.txt B10 "B10 main"
    edit_line C.txt C48 "C48 main"
    git commit -qam "main moves" && git push -q origin main
    git checkout -q pr
    git rebase -q main
}

run_delta() {
    OUT=$("$DELTA" "$@" 2>"$ROOT/stderr")
    CODE=$?
    ERR=$(cat "$ROOT/stderr")
}

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $label"
        echo "  expected: $expected"
        echo "  got: $actual"
    fi
}

assert_contains() {
    local label="$1" pattern="$2" output="$3"
    TOTAL=$((TOTAL + 1))
    if printf '%s\n' "$output" | grep -qF -- "$pattern"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $label"
        echo "  expected to contain: $pattern"
        echo "  got: $output"
    fi
}

assert_not_contains() {
    local label="$1" pattern="$2" output="$3"
    TOTAL=$((TOTAL + 1))
    if printf '%s\n' "$output" | grep -qF -- "$pattern"; then
        FAIL=$((FAIL + 1))
        echo "FAIL: $label"
        echo "  expected NOT to contain: $pattern"
        echo "  got: $output"
    else
        PASS=$((PASS + 1))
    fi
}

# ── Scenarios ────────────────────────────────────────────

test_plain_new_commit() {
    setup_repo
    local old new
    old=$(open_pr)
    edit_line B.txt "B70" "B70 fix"
    new=$(commit_push "pr round 2")
    run_delta "$old" "$new" main
    assert_eq "plain commit: exit 0" 0 "$CODE"
    assert_contains "plain commit: B in target" "+++ b/B.txt" "$OUT"
    assert_contains "plain commit: the new line" "+B70 fix" "$OUT"
    assert_not_contains "plain commit: A left out" "A.txt" "$OUT"
    assert_not_contains "plain commit: round 1 line left out" "+B50 pr" "$OUT"
    assert_eq "plain commit: quiet stderr" "" "$ERR"
    teardown
}

test_rebase_with_author_change() {
    setup_repo
    local old new
    old=$(open_pr)
    move_main_and_rebase
    edit_line B.txt "B50 pr" "B50 pr v2"
    new=$(commit_push "pr round 2")
    run_delta "$old" "$new" main
    assert_eq "rebase + change: exit 0" 0 "$CODE"
    assert_contains "rebase + change: author line" "+B50 pr v2" "$OUT"
    assert_not_contains "rebase + change: main's edit to B left out" "B10 main" "$OUT"
    assert_not_contains "rebase + change: shifted A left out" "A.txt" "$OUT"
    assert_not_contains "rebase + change: C with main's context edit left out" "C.txt" "$OUT"
    assert_not_contains "rebase + change: untouched D left out" "D.txt" "$OUT"
    teardown
}

test_clean_rebase() {
    setup_repo
    local old new
    old=$(open_pr)
    move_main_and_rebase
    git push -q -f origin pr 2>/dev/null
    new=$(git rev-parse HEAD)
    run_delta "$old" "$new" main
    assert_eq "clean rebase: exit 0" 0 "$CODE"
    assert_eq "clean rebase: empty target" "" "$OUT"
    teardown
}

test_file_added_in_round_2() {
    setup_repo
    local old new
    old=$(open_pr)
    printf 'E1\nE2\n' > E.txt && git add E.txt
    new=$(commit_push "pr round 2")
    run_delta "$old" "$new" main
    assert_contains "added file: E in target" "+++ b/E.txt" "$OUT"
    assert_contains "added file: its lines" "+E2" "$OUT"
    assert_not_contains "added file: B left out" "B.txt" "$OUT"
    teardown
}

test_author_deletes_lines() {
    setup_repo
    local old new
    old=$(open_pr)
    sed -i '/^B80$/d' B.txt
    new=$(commit_push "pr round 2")
    run_delta "$old" "$new" main
    assert_contains "deleted line: B in target" "+++ b/B.txt" "$OUT"
    assert_contains "deleted line: the removal" "-B80" "$OUT"
    teardown
}

test_file_left_pr() {
    setup_repo
    local old new
    old=$(open_pr)
    edit_line B.txt "B50 pr" "B50"
    new=$(commit_push "pr round 2")
    run_delta "$old" "$new" main
    assert_eq "file left PR: exit 0" 0 "$CODE"
    assert_not_contains "file left PR: B not in target" "B.txt" "$OUT"
    teardown
}

test_author_changes_binary() {
    setup_repo
    local old new
    git checkout -q -b pr
    printf '\x00\x01round1' > bin.dat && git add bin.dat
    old=$(commit_push "pr round 1")
    printf '\x00\x01round2' > bin.dat
    new=$(commit_push "pr round 2")
    run_delta "$old" "$new" main
    assert_contains "binary change: file in target" "bin.dat" "$OUT"
    teardown
}

test_author_changes_mode() {
    setup_repo
    local old new
    old=$(open_pr)
    chmod +x A.txt
    new=$(commit_push "pr round 2")
    run_delta "$old" "$new" main
    assert_contains "mode change: file in target" "+++ b/A.txt" "$OUT"
    assert_contains "mode change: the new mode" "new mode 100755" "$OUT"
    teardown
}

test_old_head_only_on_origin() {
    setup_repo
    local old new
    old=$(open_pr)
    move_main_and_rebase
    edit_line B.txt "B50 pr" "B50 pr v2"
    new=$(commit_push "pr round 2")
    # file:// forces the network transport: a plain path clone copies every
    # object, unreachable ones included.
    git clone -q "file://$ROOT/origin.git" "$ROOT/fresh" 2>/dev/null
    cd "$ROOT/fresh"
    if git cat-file -e "$old^{commit}" 2>/dev/null; then
        echo "SETUP ERROR: fresh clone already has the force-pushed head"
    fi
    run_delta "$old" "$new" main
    assert_eq "old head fetched from origin: exit 0" 0 "$CODE"
    assert_contains "old head fetched from origin: author line" "+B50 pr v2" "$OUT"
    teardown
}

test_unknown_old_sha() {
    setup_repo
    local new
    new=$(open_pr)
    run_delta 0000000000000000000000000000000000000000 "$new" main
    assert_eq "unknown old sha: exit 3" 3 "$CODE"
    assert_contains "unknown old sha: says which commit" "0000000000000000000000000000000000000000" "$ERR"
    teardown
}

test_usage() {
    setup_repo
    run_delta only two
    assert_eq "usage: exit 2" 2 "$CODE"
    assert_contains "usage: prints usage" "usage: review-delta" "$ERR"
    teardown
}

test_plain_new_commit
test_rebase_with_author_change
test_clean_rebase
test_file_added_in_round_2
test_author_deletes_lines
test_file_left_pr
test_author_changes_binary
test_author_changes_mode
test_old_head_only_on_origin
test_unknown_old_sha
test_usage

echo ""
echo "review-delta: $PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ]
