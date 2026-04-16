#!/bin/bash
# Reminds Claude to update session state after Edit/Write operations.
# Runs on PostToolUse for Write|Edit|NotebookEdit. Silent when no active session.

set -euo pipefail

TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0

# Only run in projects that use flowyeah
[ -f "$TOPLEVEL/flowyeah.yml" ] || exit 0

# Fire if there's an active build or review session
if [ -f "$TOPLEVEL/.flowyeah/state.md" ]; then
    echo "Session active: Update .flowyeah/state.md if you made progress."
else
    shopt -s nullglob
    REVIEW_FILES=("$TOPLEVEL"/.flowyeah/review-state-*.md)
    RESPOND_FILES=("$TOPLEVEL"/.flowyeah/respond-state-*.md)
    shopt -u nullglob
    if [ ${#REVIEW_FILES[@]} -gt 0 ]; then
        echo "Session active: Update $(basename "${REVIEW_FILES[0]}") if you made progress."
    elif [ ${#RESPOND_FILES[@]} -gt 0 ]; then
        if [ ${#RESPOND_FILES[@]} -eq 1 ]; then
            echo "Session active: Update $(basename "${RESPOND_FILES[0]}") if you made progress."
        else
            NAMES=""
            for f in "${RESPOND_FILES[@]}"; do
                NAMES="${NAMES:+$NAMES, }$(basename "$f")"
            done
            echo "Sessions active: Update $NAMES if you made progress."
        fi
    else
        exit 0
    fi
fi
