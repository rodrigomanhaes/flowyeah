#!/bin/bash
# Injects active flowyeah session state into every prompt for context recovery.
# Runs on UserPromptSubmit. Silent when no flowyeah project or no active session.

set -euo pipefail

TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0

# Only run in projects that use flowyeah
[ -f "$TOPLEVEL/flowyeah.yml" ] || exit 0

# Build a "(PR #N, branch X)" suffix for a session header.
# Args: $1 = state file, $2 = filename prefix (e.g., "review-state-")
session_header_suffix() {
    local state_file="$1" prefix="$2" number file_branch suffix
    number="${state_file##*$prefix}"
    number="${number%.md}"
    file_branch=$(grep -m1 '^Branch:' "$state_file" 2>/dev/null | cut -d' ' -f2-)
    suffix="(PR #${number}"
    [ -n "$file_branch" ] && suffix="${suffix}, branch ${file_branch}"
    suffix="${suffix})"
    echo "$suffix"
}

# ── Review sessions (one entry per active PR; PR-labeled headers) ──
shopt -s nullglob
REVIEW_STATE_FILES=("$TOPLEVEL"/.flowyeah/review-state-*.md)
shopt -u nullglob

for state_file in "${REVIEW_STATE_FILES[@]}"; do
    number="${state_file##*review-state-}"
    number="${number%.md}"
    suffix=$(session_header_suffix "$state_file" "review-state-")

    echo "───── flowyeah:review session ${suffix} ─────"
    echo ""
    echo "## STATE"
    cat "$state_file"
    echo ""

    if [ -f "$TOPLEVEL/.flowyeah/review-approved-${number}.md" ]; then
        echo "## APPROVED FINDINGS"
        grep -E '^## Finding |^- File:|^- Label:' "$TOPLEVEL/.flowyeah/review-approved-${number}.md" 2>/dev/null || echo "(no approved findings yet)"
        echo ""
    fi

    if [ -f "$TOPLEVEL/.flowyeah/own-rejections-${number}.md" ]; then
        REJ_COUNT=$(grep -c '^## Rejection ' "$TOPLEVEL/.flowyeah/own-rejections-${number}.md" 2>/dev/null || echo 0)
        if [ "$REJ_COUNT" -gt 0 ]; then
            echo "Previously rejected: $REJ_COUNT (see .flowyeah/own-rejections-${number}.md for reasoning)"
            echo ""
        fi
    fi

    echo "──────────────────────────────────────────────"
    echo ""
done

# ── Respond sessions (one entry per active PR; PR-labeled headers) ──
shopt -s nullglob
RESPOND_STATE_FILES=("$TOPLEVEL"/.flowyeah/respond-state-*.md)
shopt -u nullglob

for state_file in "${RESPOND_STATE_FILES[@]}"; do
    number="${state_file##*respond-state-}"
    number="${number%.md}"
    suffix=$(session_header_suffix "$state_file" "respond-state-")

    echo "───── flowyeah:respond session ${suffix} ─────"
    echo ""
    echo "## STATE"
    cat "$state_file"
    echo ""

    if [ -f "$TOPLEVEL/.flowyeah/respond-decisions-${number}.md" ]; then
        echo "## TRIAGE DECISIONS"
        grep -E '^## (Comment|Finding) |^- File:|^- Action:|^- Thread:' "$TOPLEVEL/.flowyeah/respond-decisions-${number}.md" 2>/dev/null || echo "(no decisions yet)"
        echo ""
    fi

    echo "──────────────────────────────────────────────"
    echo ""
done

# ── Build session: either in current worktree or scan .flowyeah/worktrees/ ──
SESSION_DIR=""

if [ -f "$TOPLEVEL/.flowyeah/state.md" ]; then
    # We're inside a worktree with an active session
    SESSION_DIR="$TOPLEVEL/.flowyeah"
elif [ -d "$TOPLEVEL/.flowyeah/worktrees" ]; then
    # We're in the main checkout — scan worktrees for active sessions.
    # This glob works because the build skill places worktrees at
    # .flowyeah/worktrees/<type>-<slug>, and session files at .flowyeah/
    # inside each worktree root — so the path is .flowyeah/worktrees/<name>/.flowyeah/.
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

# Detect and validate session type (review sessions use review-state-*.md above, never reach here)
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

    # Inject process skills enforcement from flowyeah.yml
    SKILLS=""
    for phase in brainstorming planning tdd debugging; do
        SKILL=$(awk -v phase="$phase" '
            /^  process_skills:/ { in_block=1; next }
            in_block && /^  [^ ]/ { in_block=0 }
            in_block && $0 ~ "^    " phase ":" {
                sub(/^    [a-z]+: */, "")
                sub(/ *#.*$/, "")
                gsub(/["'"'"']/, "")
                if ($0 == "null" || $0 == "~" || $0 == "") next
                print; exit
            }
        ' "$TOPLEVEL/flowyeah.yml" 2>/dev/null)
        if [ -n "$SKILL" ]; then
            SKILLS="${SKILLS:+$SKILLS, }$phase=$SKILL"
        fi
    done
    if [ -n "$SKILLS" ]; then
        echo "## PROCESS SKILLS (mandatory)"
        echo "You MUST invoke these skills via the Skill tool at the corresponding pipeline phase:"
        echo "$SKILLS" | tr ',' '\n' | while read -r entry; do
            entry=$(echo "$entry" | xargs)
            phase="${entry%%=*}"
            skill="${entry#*=}"
            echo "  - $phase → $skill"
        done
        echo ""
    fi
fi

echo "──────────────────────────────────────────────"

# ── Pipeline reminder: extract unchecked items and repeat at the end ──
if [ "$SESSION_TYPE" = "build" ] && [ -f "$SESSION_DIR/progress.md" ]; then
    UNCHECKED=$(awk '/^## Pipeline$/{ in_pipeline=1; next } /^## /{ in_pipeline=0 } in_pipeline && /^- \[ \] / { print }' "$SESSION_DIR/progress.md")
    if [ -n "$UNCHECKED" ]; then
        echo ""
        echo "⚠️ REMAINING PIPELINE STEPS — DO NOT SKIP:"
        echo "$UNCHECKED"
    fi
fi
