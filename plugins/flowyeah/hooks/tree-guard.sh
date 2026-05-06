#!/bin/bash
# Blocks tree-mutating git commands in the primary checkout while any flowyeah
# review, respond, or build session is active. Mutations belonging to those
# pipelines must happen in dedicated worktrees:
#   review  → .flowyeah/review-worktrees/{N}/   (created by review on demand)
#   respond → .flowyeah/worktrees/{branch}/      (created by respond step 5)
#   build   → .flowyeah/worktrees/{name}/        (created by build step 3)
# Inside any worktree under .flowyeah/worktrees/ or .flowyeah/review-worktrees/,
# this hook stays out of the way — those are the sanctioned places to mutate.
#
# Detection signals:
#   review/respond → state files at .flowyeah/{review,respond}-state-{N}.md in
#                    the primary checkout, matched by current branch.
#   build          → state file inside the worktree at
#                    .flowyeah/worktrees/{name}/.flowyeah/state.md. No branch
#                    correlation — the primary checkout is by definition on a
#                    different branch than any active build worktree.
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

# Find an active session. Precedence order: review → respond → build. Review
# and respond match by current branch; build matches by mere existence of any
# state file inside a worktree, since the primary is by definition on a
# different branch.
SESSION_TYPE=""
SESSION_ID=""        # PR/MR number for review/respond; worktree name for build
SESSION_DESCRIPTOR=""

shopt -s nullglob
if [ -n "$CURRENT_BRANCH" ]; then
    for state_file in "$TOPLEVEL"/.flowyeah/review-state-*.md; do
        FILE_BRANCH=$(grep -m1 '^Branch:' "$state_file" 2>/dev/null | cut -d' ' -f2-)
        if [ "$FILE_BRANCH" = "$CURRENT_BRANCH" ]; then
            number="${state_file##*review-state-}"
            SESSION_ID="${number%.md}"
            SESSION_TYPE="review"
            SESSION_DESCRIPTOR="review session for PR/MR #${SESSION_ID} (branch: ${CURRENT_BRANCH})"
            break
        fi
    done

    if [ -z "$SESSION_TYPE" ]; then
        for state_file in "$TOPLEVEL"/.flowyeah/respond-state-*.md; do
            FILE_BRANCH=$(grep -m1 '^Branch:' "$state_file" 2>/dev/null | cut -d' ' -f2-)
            if [ "$FILE_BRANCH" = "$CURRENT_BRANCH" ]; then
                number="${state_file##*respond-state-}"
                SESSION_ID="${number%.md}"
                SESSION_TYPE="respond"
                SESSION_DESCRIPTOR="respond session for PR/MR #${SESSION_ID} (branch: ${CURRENT_BRANCH})"
                break
            fi
        done
    fi
fi

if [ -z "$SESSION_TYPE" ]; then
    for state_file in "$TOPLEVEL"/.flowyeah/worktrees/*/.flowyeah/state.md; do
        if [ -f "$state_file" ]; then
            wt_path="${state_file%/.flowyeah/state.md}"
            SESSION_ID="${wt_path##*/}"
            SESSION_TYPE="build"
            SESSION_DESCRIPTOR="build session in worktree ${SESSION_ID}"
            break
        fi
    done
fi
shopt -u nullglob

[ -n "$SESSION_TYPE" ] || exit 0

# Session-specific guidance for the error message.
case "$SESSION_TYPE" in
    review)
        WORKTREE_PATH=".flowyeah/review-worktrees/${SESSION_ID}/"
        WORKTREE_PURPOSE="run code at PR HEAD, apply a candidate patch, full-tree LSP"
        EXIT_HINT="To exit the review session entirely:

    /flowyeah:review finalize ${SESSION_ID}"
        ;;
    respond)
        WORKTREE_PATH=".flowyeah/worktrees/${CURRENT_BRANCH}/"
        WORKTREE_PURPOSE="implement fixes for triaged findings (respond step 6)"
        EXIT_HINT="Complete the respond pipeline through step 10 (cleanup), or
remove .flowyeah/respond-state-${SESSION_ID}.md and
.flowyeah/respond-decisions-${SESSION_ID}.md to abort."
        ;;
    build)
        WORKTREE_PATH=".flowyeah/worktrees/${SESSION_ID}/"
        WORKTREE_PURPOSE="implement, commit, test, push for the build pipeline"
        EXIT_HINT="Complete the build pipeline through step 10 (cleanup), or
run \`/flowyeah:status clean\` to remove stale build sessions."
        ;;
esac

cat >&2 <<EOF
flowyeah:tree-guard blocked this command.

An active ${SESSION_DESCRIPTOR} is in progress. The pipeline must not mutate
the working tree, index, or HEAD of the primary checkout (your current cwd).
Forbidden in the primary checkout:

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
