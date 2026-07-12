#!/bin/bash
# Reminds Claude to update session state after Edit/Write operations.
# Runs on PostToolUse for Write|Edit|NotebookEdit. Silent when no active session.
#
# PostToolUse stdout with exit 0 is transcript-only — to reach model context
# the reminder must travel in the hookSpecificOutput.additionalContext JSON
# field. Session filenames contain only [A-Za-z0-9._-], so no JSON escaping
# is needed when interpolating them.

set -euo pipefail

TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0

# Only run in projects that use flowyeah
[ -f "$TOPLEVEL/flowyeah.yml" ] || exit 0

# Collect every active session: build (state.md), review, respond.
NAMES=""
if [ -f "$TOPLEVEL/.flowyeah/state.md" ]; then
    NAMES=".flowyeah/state.md"
fi
shopt -s nullglob
for f in "$TOPLEVEL"/.flowyeah/review-state-*.md "$TOPLEVEL"/.flowyeah/respond-state-*.md; do
    NAMES="${NAMES:+$NAMES, }$(basename "$f")"
done
shopt -u nullglob

[ -n "$NAMES" ] || exit 0

printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"Session active: Update %s if you made progress."}}\n' "$NAMES"
