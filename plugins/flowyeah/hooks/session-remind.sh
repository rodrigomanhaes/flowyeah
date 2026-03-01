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
elif [ -f "$TOPLEVEL/.flowyeah/review-state.md" ]; then
    echo "Session active: Update .flowyeah/review-state.md if you made progress."
else
    exit 0
fi
