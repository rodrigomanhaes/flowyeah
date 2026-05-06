#!/bin/bash
# Blocks tree-mutating git commands in the primary checkout while a flowyeah
# review or respond session is active for the current branch. Mutations
# belonging to those pipelines must happen in dedicated worktrees:
#   review  → .flowyeah/review-worktrees/{N}/   (created by review on demand)
#   respond → .flowyeah/worktrees/{branch}/      (created by respond step 5)
# Inside any worktree under .flowyeah/worktrees/ or .flowyeah/review-worktrees/,
# this hook stays out of the way — those are the sanctioned places to mutate.
#
# Runs as PreToolUse on Bash. Exit 2 + stderr blocks the call and surfaces the
# message to the model. Any other failure mode silently allows the command —
# the hook must never lock the user out due to its own bugs.

set -uo pipefail

# Read JSON payload from stdin. If anything fails here, allow the command.
INPUT=$(cat 2>/dev/null) || exit 0
[ -n "$INPUT" ] || exit 0

# Tolerate environments without jq by short-circuiting; the hook is a guard,
# not a hard gate.
command -v jq >/dev/null 2>&1 || exit 0

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$TOOL_NAME" = "Bash" ] || exit 0

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -n "$COMMAND" ] || exit 0

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$CWD" ] && [ -d "$CWD" ] || CWD="$PWD"

TOPLEVEL=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || exit 0

# Only act in flowyeah projects.
[ -f "$TOPLEVEL/flowyeah.yml" ] || exit 0

# If cwd is inside any flowyeah-managed worktree, allow — mutations there are
# sanctioned by both review and respond.
case "$TOPLEVEL" in
    */.flowyeah/worktrees/*) exit 0 ;;
    */.flowyeah/review-worktrees/*) exit 0 ;;
esac

# Detect the mutating git verbs. Match `git <verb>` with optional whitespace,
# anywhere in the command (covers `cd x && git checkout ...`, `sudo git ...`,
# pipelines, etc.). `git fetch` is intentionally NOT blocked — it only updates
# refs.
MUTATING_RE='(^|[^a-zA-Z0-9_-])git[[:space:]]+(checkout|checkout-index|restore|switch|reset|apply|am|merge|rebase|pull|stash|clean)([[:space:]]|$)'
if ! [[ "$COMMAND" =~ $MUTATING_RE ]]; then
    exit 0
fi

CURRENT_BRANCH=$(git -C "$TOPLEVEL" branch --show-current 2>/dev/null)
[ -n "$CURRENT_BRANCH" ] || exit 0

# Find an active session — review takes precedence over respond if both match
# the current branch (same PR). Either way the rule is identical: don't mutate
# the primary checkout.
SESSION_TYPE=""
ACTIVE_PR=""

shopt -s nullglob
for state_file in "$TOPLEVEL"/.flowyeah/review-state-*.md; do
    FILE_BRANCH=$(grep -m1 '^Branch:' "$state_file" 2>/dev/null | cut -d' ' -f2-)
    if [ "$FILE_BRANCH" = "$CURRENT_BRANCH" ]; then
        number="${state_file##*review-state-}"
        ACTIVE_PR="${number%.md}"
        SESSION_TYPE="review"
        break
    fi
done

if [ -z "$SESSION_TYPE" ]; then
    for state_file in "$TOPLEVEL"/.flowyeah/respond-state-*.md; do
        FILE_BRANCH=$(grep -m1 '^Branch:' "$state_file" 2>/dev/null | cut -d' ' -f2-)
        if [ "$FILE_BRANCH" = "$CURRENT_BRANCH" ]; then
            number="${state_file##*respond-state-}"
            ACTIVE_PR="${number%.md}"
            SESSION_TYPE="respond"
            break
        fi
    done
fi
shopt -u nullglob

[ -n "$SESSION_TYPE" ] || exit 0

# Build session-specific guidance for the error message.
if [ "$SESSION_TYPE" = "review" ]; then
    WORKTREE_PATH=".flowyeah/review-worktrees/${ACTIVE_PR}/"
    WORKTREE_PURPOSE="run code at PR HEAD, apply a candidate patch, full-tree LSP"
    EXIT_HINT="To exit the review session entirely:

    /flowyeah:review finalize ${ACTIVE_PR}"
else
    WORKTREE_PATH=".flowyeah/worktrees/${CURRENT_BRANCH}/"
    WORKTREE_PURPOSE="implement fixes for triaged findings (respond step 6)"
    EXIT_HINT="Complete the respond pipeline through step 10 (cleanup), or
remove .flowyeah/respond-state-${ACTIVE_PR}.md and
.flowyeah/respond-decisions-${ACTIVE_PR}.md to abort."
fi

cat >&2 <<EOF
flowyeah:tree-guard blocked this command.

An active ${SESSION_TYPE} session for PR/MR #${ACTIVE_PR} (branch: ${CURRENT_BRANCH})
is in progress in this primary checkout. The pipeline must not mutate the
working tree, index, or HEAD here. Forbidden in the primary checkout:

    git checkout / checkout-index / restore / switch / reset / apply / am
    git merge / rebase / pull / stash / clean

Allowed alternatives:

  * Read content at any SHA:    git show <sha>:<file>
  * Per-line authorship:        git blame <sha> -- <file>
  * PR diff / files / commits:  via the adapter (gh pr diff, etc.)
  * Update refs only:           git fetch  (this hook does not block it)

If you need to ${WORKTREE_PURPOSE}, do it inside the dedicated worktree at:

    ${WORKTREE_PATH}

${EXIT_HINT}

Do not retry this command unless you have moved into the worktree or exited
the active session.
EOF
exit 2
