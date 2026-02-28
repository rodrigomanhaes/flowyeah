#!/bin/bash
# Reminds Claude to update session state after Edit/Write operations.
# Runs on PostToolUse for Edit|Write. Silent when no active session.

set -euo pipefail

TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0

# Only fire if there's an active session in the current worktree
[ -d "$TOPLEVEL/.flowyeah" ] || exit 0

echo "Session active: Update .flowyeah/state.md if you made progress."
