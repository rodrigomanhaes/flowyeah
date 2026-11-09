#!/bin/bash
# Decides whether a flowyeah state file belongs to the conversation running the hook.
# Sourced by session-inject.sh and session-remind.sh.
#
# Claude Code sends the conversation's session_id in every hook's stdin payload;
# the skills record theirs in the state file's Session: line. A state file is
# this conversation's only when the two match. Without a session_id (no payload,
# no jq, unparsable payload) no state file can be shown to belong here.

CURRENT_SESSION=""
if [ ! -t 0 ] && command -v jq >/dev/null 2>&1; then
    CURRENT_SESSION=$(jq -r '.session_id // empty' 2>/dev/null || true)
fi

# Args: $1 = state file
owned_by_current_session() {
    local owner
    [ -n "$CURRENT_SESSION" ] || return 1
    owner=$(grep -m1 '^Session:' "$1" 2>/dev/null | cut -d' ' -f2- || true)
    [ "$owner" = "$CURRENT_SESSION" ]
}
