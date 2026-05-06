#!/bin/bash
# Blocks tree-mutating git commands in the primary checkout while a flowyeah
# review session is active for the current branch. Mutations belonging to the
# review pipeline must happen in a dedicated worktree under
# .flowyeah/review-worktrees/{N}/ (see SKILL.md "Invariant: Primary Checkout
# Is Untouched"). Inside that worktree, or inside any build worktree under
# .flowyeah/worktrees/, this hook stays out of the way.
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

# If cwd is inside a build worktree or a review worktree, allow — those are
# the sanctioned places to mutate.
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

# Find an active review session whose Branch matches the current branch.
CURRENT_BRANCH=$(git -C "$TOPLEVEL" branch --show-current 2>/dev/null)
[ -n "$CURRENT_BRANCH" ] || exit 0

shopt -s nullglob
REVIEW_STATE_FILES=("$TOPLEVEL"/.flowyeah/review-state-*.md)
shopt -u nullglob

ACTIVE_PR=""
for state_file in "${REVIEW_STATE_FILES[@]}"; do
    FILE_BRANCH=$(grep -m1 '^Branch:' "$state_file" 2>/dev/null | cut -d' ' -f2-)
    if [ "$FILE_BRANCH" = "$CURRENT_BRANCH" ]; then
        number="${state_file##*review-state-}"
        ACTIVE_PR="${number%.md}"
        break
    fi
done

[ -n "$ACTIVE_PR" ] || exit 0

# Block.
cat >&2 <<EOF
flowyeah:review-tree-guard blocked this command.

An active review session for PR/MR #${ACTIVE_PR} (branch: ${CURRENT_BRANCH}) is
in progress in this primary checkout. The review pipeline must not mutate the
working tree, index, or HEAD here. Forbidden in the primary checkout:

    git checkout / checkout-index / restore / switch / reset / apply / am
    git merge / rebase / pull / stash / clean

Allowed alternatives:

  * Read content at any SHA:    git show <sha>:<file>
  * Per-line authorship:        git blame <sha> -- <file>
  * PR diff / files / commits:  via the review adapter (gh pr diff, etc.)
  * Update refs only:           git fetch  (this hook does not block it)

If you genuinely need to materialize files at a different ref (run code at PR
HEAD, apply a candidate patch, full-tree LSP), create a review worktree at
.flowyeah/review-worktrees/${ACTIVE_PR}/ and do the work there. Record the path
in Worktree: inside .flowyeah/review-state-${ACTIVE_PR}.md so finalize can clean it up.

To exit the review session entirely:

    /flowyeah:review finalize ${ACTIVE_PR}

Do not retry this command unless you have moved into the review worktree or
finalized the session.
EOF
exit 2
