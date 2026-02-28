#!/bin/bash
# Injects active flowyeah session state into every prompt for context recovery.
# Runs on UserPromptSubmit. Silent when no flowyeah project or no active session.

set -euo pipefail

TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0

# Only run in projects that use flowyeah
[ -f "$TOPLEVEL/flowyeah.yml" ] || exit 0

# Find session: either in current worktree or scan .flowyeah/worktrees/
SESSION_DIR=""

if [ -f "$TOPLEVEL/.flowyeah/state.md" ]; then
    # We're inside a worktree with an active session
    SESSION_DIR="$TOPLEVEL/.flowyeah"
elif [ -d "$TOPLEVEL/.flowyeah/worktrees" ]; then
    # We're in the main checkout — count active sessions
    SESSIONS=()
    shopt -s nullglob
    for dir in "$TOPLEVEL"/.flowyeah/worktrees/*/.flowyeah; do
        SESSIONS+=("$dir")
    done
    shopt -u nullglob

    if [ ${#SESSIONS[@]} -eq 0 ]; then
        exit 0
    elif [ ${#SESSIONS[@]} -eq 1 ]; then
        SESSION_DIR="${SESSIONS[0]}"
        echo "───── flowyeah:build: Active session found in $(dirname "$SESSION_DIR" | xargs basename) ─────"
        echo ""
    else
        echo "───── flowyeah:build: ${#SESSIONS[@]} active sessions ─────"
        echo ""
        for dir in "${SESSIONS[@]}"; do
            WT_NAME=$(dirname "$dir" | xargs basename)
            TASK=$(grep -m1 '^Task:' "$dir/state.md" 2>/dev/null | sed 's/^Task: //' || echo "unknown")
            STEP=$(grep -m1 '^Step:' "$dir/state.md" 2>/dev/null | sed 's/^Step: //' || echo "unknown")
            echo "  - $WT_NAME → $TASK ($STEP)"
        done
        echo ""
        echo "Run flowyeah:build from the main checkout to choose, or cd into a worktree."
        echo "──────────────────────────────────────────────"
        exit 0
    fi
else
    exit 0
fi

# Inject session state
echo "───── flowyeah:build session ─────"
echo ""

echo "## MISSION"
if [ -f "$SESSION_DIR/mission.md" ]; then
    cat "$SESSION_DIR/mission.md"
else
    echo "(not set)"
fi
echo ""

echo "## PROGRESS"
if [ -f "$SESSION_DIR/progress.md" ]; then
    cat "$SESSION_DIR/progress.md"
else
    echo "(not set)"
fi
echo ""

echo "## STATE"
if [ -f "$SESSION_DIR/state.md" ]; then
    cat "$SESSION_DIR/state.md"
else
    echo "(not set)"
fi
echo ""

echo "## FINDINGS"
if [ -f "$SESSION_DIR/findings.md" ]; then
    SUMMARY=$(awk '/^## Summary$/{found=1;next} /^## /{found=0} found' "$SESSION_DIR/findings.md")
    if [ -n "$SUMMARY" ]; then
        echo "$SUMMARY"
    else
        echo "(no summary yet)"
    fi
    echo "(full details: $SESSION_DIR/findings.md)"
else
    echo "(none yet)"
fi

echo "──────────────────────────────────────────────"
