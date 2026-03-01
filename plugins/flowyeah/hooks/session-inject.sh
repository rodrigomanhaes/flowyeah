#!/bin/bash
# Injects active flowyeah session state into every prompt for context recovery.
# Runs on UserPromptSubmit. Silent when no flowyeah project or no active session.

set -euo pipefail

TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0

# Only run in projects that use flowyeah
[ -f "$TOPLEVEL/flowyeah.yml" ] || exit 0

# ── Review session (separate file, never conflicts with build) ──
if [ -f "$TOPLEVEL/.flowyeah/review-state.md" ]; then
    echo "───── flowyeah:review session ─────"
    echo ""
    echo "## STATE"
    cat "$TOPLEVEL/.flowyeah/review-state.md"
    echo ""
    echo "──────────────────────────────────────────────"
    echo ""
fi

# ── Build session: either in current worktree or scan .flowyeah/worktrees/ ──
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
        echo "───── flowyeah:build: Active session found in $(basename "$(dirname "$SESSION_DIR")") ─────"
        echo ""
    else
        echo "───── flowyeah:build: ${#SESSIONS[@]} active sessions ─────"
        echo ""
        for dir in "${SESSIONS[@]}"; do
            WT_NAME=$(basename "$(dirname "$dir")")
            TASK=$(grep -m1 '^Task:' "$dir/state.md" 2>/dev/null | cut -d' ' -f2- || echo "unknown")
            STEP=$(grep -m1 '^Step:' "$dir/state.md" 2>/dev/null | cut -d' ' -f2- || echo "unknown")
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

# Detect and validate session type (review sessions use review-state.md above, never reach here)
SESSION_TYPE=$(grep -m1 '^Type:' "$SESSION_DIR/state.md" 2>/dev/null | cut -d' ' -f2- || echo "build")
if [ "$SESSION_TYPE" != "build" ]; then
    SESSION_TYPE="build"
fi

# Inject session state
echo "───── flowyeah:${SESSION_TYPE} session ─────"
echo ""

if [ "$SESSION_TYPE" = "build" ]; then
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
fi

echo "## STATE"
if [ -f "$SESSION_DIR/state.md" ]; then
    cat "$SESSION_DIR/state.md"
else
    echo "(not set)"
fi
echo ""

if [ "$SESSION_TYPE" = "build" ]; then
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
    echo ""
fi

echo "──────────────────────────────────────────────"
