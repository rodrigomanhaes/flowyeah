#!/bin/bash
# Cross-reference consistency tests for flowyeah prose files.
# Run from anywhere: bash plugins/flowyeah/tests/test-consistency.sh

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"

PASS=0
FAIL=0
TOTAL=0

# ── Key paths ────────────────────────────────────────────

README="$PLUGIN_DIR/../../README.md"
SCHEMA="$PLUGIN_DIR/config-schema.md"
SETUP="$PLUGIN_DIR/setup.md"
CHECK_SKILL="$PLUGIN_DIR/skills/check/SKILL.md"
BUILD_SKILL="$PLUGIN_DIR/skills/build/SKILL.md"

# ── Helpers ──────────────────────────────────────────────

assert_file_exists() {
    local label="$1" path="$2"
    TOTAL=$((TOTAL + 1))
    if [ -f "$path" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $label"
        echo "  expected file to exist: $path"
    fi
}

assert_contains() {
    local label="$1" pattern="$2" file="$3"
    TOTAL=$((TOTAL + 1))
    if grep -qF "$pattern" "$file"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $label"
        echo "  expected to find: $pattern"
        echo "  in: $file"
    fi
}

assert_not_contains() {
    local label="$1" pattern="$2" file="$3"
    TOTAL=$((TOTAL + 1))
    if grep -qF -- "$pattern" "$file"; then
        FAIL=$((FAIL + 1))
        echo "FAIL: $label"
        echo "  expected NOT to find: $pattern"
        echo "  in: $file"
    else
        PASS=$((PASS + 1))
    fi
}

assert_dir_in_list() {
    local label="$1" dirname="$2" list="$3"
    TOTAL=$((TOTAL + 1))
    if echo "$list" | grep -qxF "$dirname"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $label"
        echo "  expected '$dirname' in list"
    fi
}

# ── Section: Critical files ──────────────────────────────

echo "=== Critical files ==="

assert_file_exists "config-schema.md exists" "$SCHEMA"
assert_file_exists "setup.md exists" "$SETUP"

for dir in "$PLUGIN_DIR"/adapters/*/; do
    name="$(basename "$dir")"
    # Directories starting with _ are shared docs, not platform adapters.
    case "$name" in _*) continue ;; esac
    assert_file_exists "adapter $name has connection.md" "$dir/connection.md"
done

for dir in "$PLUGIN_DIR"/skills/*/; do
    name="$(basename "$dir")"
    assert_file_exists "skill $name has SKILL.md" "$dir/SKILL.md"
done

# ── Section: Manifest version sync ───────────────────────
# The pre-commit hook bumps plugin.json and marketplace.json together, but
# git merges and --no-verify commits bypass it — drift must fail CI.

echo ""
echo "=== Manifest version sync ==="

PLUGIN_JSON="$PLUGIN_DIR/.claude-plugin/plugin.json"
MARKETPLACE_JSON="$PLUGIN_DIR/../../.claude-plugin/marketplace.json"

PLUGIN_VERSION=$(grep -o '"version": *"[^"]*"' "$PLUGIN_JSON" | sed 's/.*"\(.*\)"/\1/')

TOTAL=$((TOTAL + 1))
if [ -n "$PLUGIN_VERSION" ] && [ "$(printf '%s\n' "$PLUGIN_VERSION" | wc -l)" -eq 1 ]; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
    echo "FAIL: plugin.json declares exactly one version"
    echo "  got: $PLUGIN_VERSION"
fi

MARKETPLACE_VERSIONS=$(grep -o '"version": *"[^"]*"' "$MARKETPLACE_JSON" | sed 's/.*"\(.*\)"/\1/')

TOTAL=$((TOTAL + 1))
if [ "$(printf '%s\n' "$MARKETPLACE_VERSIONS" | wc -l)" -eq 2 ]; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
    echo "FAIL: marketplace.json declares exactly two version fields (metadata + plugin entry)"
    echo "  got: $MARKETPLACE_VERSIONS"
fi

for v in $MARKETPLACE_VERSIONS; do
    TOTAL=$((TOTAL + 1))
    if [ "$v" = "$PLUGIN_VERSION" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: marketplace.json version matches plugin.json"
        echo "  marketplace: $v, plugin: $PLUGIN_VERSION"
    fi
done

# ── Section: README cross-references ─────────────────────

echo ""
echo "=== README cross-references ==="

for dir in "$PLUGIN_DIR"/adapters/*/; do
    name="$(basename "$dir")"
    if [ -f "$dir/source.md" ]; then
        assert_contains "adapter $name listed in README Supported Sources" "$name:" "$README"
    fi
done

for dir in "$PLUGIN_DIR"/skills/*/; do
    name="$(basename "$dir")"
    assert_contains "skill $name listed in README Skills table" "flowyeah:$name" "$README"
done

# ── Section: Source adapter completeness ─────────────────

echo ""
echo "=== Source adapter completeness ==="

# Extract adapter names from README Supported Sources table rows.
# Lines contain patterns like gitlab:#, bugsink:, newrelic:, etc.
readme_adapters=""
while IFS= read -r line; do
    # Skip URL-style sources (https://...)
    echo "$line" | grep -q '://' && continue
    # Extract the lowercase prefix after "from " (e.g., gitlab from "from gitlab:#5588")
    prefix="$(echo "$line" | sed -n 's/.*from \([a-z]\{2,\}\):.*/\1/p')"
    if [ -n "$prefix" ]; then
        readme_adapters="$readme_adapters$prefix
"
    fi
done < <(sed -n '/^##* Supported Sources/,/^##/p' "$README" | grep '|.*:.*|')

readme_adapters="$(echo "$readme_adapters" | sed '/^$/d' | sort -u)"

while IFS= read -r adapter; do
    [ -z "$adapter" ] && continue
    assert_file_exists "README source $adapter has source.md" "$PLUGIN_DIR/adapters/$adapter/source.md"
done <<< "$readme_adapters"

# ── Section: Schema ↔ check skill annotated YAML ────────

echo ""
echo "=== Schema <-> check skill annotated YAML ==="

# Extract keys from config-schema.md Current Schema table.
# Lines like: | `key.subkey` | ... — extract text between backticks in first column.
schema_keys=""
while IFS= read -r line; do
    # Extract the key between backticks after the pipe
    key="$(echo "$line" | sed -n 's/^| `\([^`]*\)`.*/\1/p')"
    if [ -n "$key" ]; then
        schema_keys="$schema_keys$key
"
    fi
done < <(sed -n '/## Current Schema/,/^##/p' "$SCHEMA" | grep '^| `')

schema_keys="$(echo "$schema_keys" | sed '/^$/d')"

while IFS= read -r key; do
    [ -z "$key" ] && continue
    # Skip adapter placeholder rows (contain '<')
    case "$key" in
        *\<*) continue ;;
    esac
    # Extract the leaf segment (last part after .)
    leaf="$(echo "$key" | sed 's/.*\.//')"
    assert_contains "schema key '$key' (leaf: $leaf) in check SKILL.md annotated YAML" "$leaf:" "$CHECK_SKILL"
done <<< "$schema_keys"

# ── Section: Validation rules integrity ──────────────────

echo ""
echo "=== Validation rules integrity ==="

# Check that every validation rule has a non-empty error message (3rd pipe-delimited column).
while IFS= read -r line; do
    # Skip header and separator rows
    case "$line" in
        *"| Rule"*) continue ;;
        *"|---"*) continue ;;
    esac
    # Extract the message (4th field = 3rd pipe-delimited column after Rule, Severity)
    message="$(echo "$line" | awk -F'|' '{print $4}' | sed 's/^ *//;s/ *$//')"
    rule="$(echo "$line" | awk -F'|' '{print $2}' | sed 's/^ *//;s/ *$//')"
    TOTAL=$((TOTAL + 1))
    if [ -n "$message" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: validation rule has empty message"
        echo "  rule: $rule"
    fi
done < <(sed -n '/## Validation Rules/,/^## /p' "$SCHEMA" | grep '^|' | grep -v '^| Rule' | grep -v '^|---')

# Check that every deprecated key has migration instructions (3rd pipe-delimited column).
while IFS= read -r line; do
    case "$line" in
        *"| Key"*) continue ;;
        *"|---"*) continue ;;
    esac
    migration="$(echo "$line" | awk -F'|' '{print $4}' | sed 's/^ *//;s/ *$//')"
    key="$(echo "$line" | awk -F'|' '{print $2}' | sed 's/^ *//;s/ *$//')"
    TOTAL=$((TOTAL + 1))
    if [ -n "$migration" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: deprecated key has no migration instructions"
        echo "  key: $key"
    fi
done < <(sed -n '/## Deprecated Keys/,/^## /p' "$SCHEMA" | grep '^|' | grep -v '^| Key' | grep -v '^|---')

# ── Section: Adapter tree in build SKILL.md ──────────────

echo ""
echo "=== Adapter tree in build SKILL.md ==="

# Extract adapter names from the ASCII tree in build SKILL.md.
# Lines like: ├── gitlab/  or └── newrelic/  or └── _shared/
# Use sed to extract the adapter directory name.
tree_adapters="$(grep -E '(├── |└── )[a-z_]+/' "$BUILD_SKILL" | sed 's/.*[├└]── //; s/\/.*//' | sort -u)"

# Actual adapter directories
real_adapters="$(ls -d "$PLUGIN_DIR"/adapters/*/ 2>/dev/null | xargs -n1 basename | sort -u)"

# Every real adapter directory is in the tree
while IFS= read -r adapter; do
    [ -z "$adapter" ] && continue
    assert_dir_in_list "real adapter $adapter in build SKILL.md tree" "$adapter" "$tree_adapters"
done <<< "$real_adapters"

# Every tree entry has an actual directory
while IFS= read -r adapter; do
    [ -z "$adapter" ] && continue
    TOTAL=$((TOTAL + 1))
    if [ -d "$PLUGIN_DIR/adapters/$adapter" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: tree entry '$adapter' has no adapter directory"
    fi
done <<< "$tree_adapters"

# ── Section: Setup template ↔ schema ───────────────────

echo ""
echo "=== Setup template <-> schema ==="

# Extract the YAML template block from setup.md (between "```yaml" and "```" in the ## Generate section)
SETUP_TEMPLATE=$(sed -n '/^## Generate/,/^## /p' "$SETUP" | sed -n '/^```yaml/,/^```/p')

# Every non-adapter, non-wildcard schema key's leaf should appear in the template
while IFS= read -r key; do
    [ -z "$key" ] && continue
    # Skip adapter placeholder rows (contain '<')
    case "$key" in
        *\<*) continue ;;
    esac
    leaf="$(echo "$key" | sed 's/.*\.//')"
    assert_contains "schema key '$key' (leaf: $leaf) in setup.md YAML template" "$leaf:" "$SETUP"
done <<< "$schema_keys"

# Hooks must use nested structure (hooks.pr.*), not flat (hooks.after_merge)
# The YAML template should contain "  pr:" under hooks, and "    after_create:" / "    after_merge:" under pr
assert_contains "setup.md template has nested hooks.pr structure" "  pr:" "$SETUP"
assert_contains "setup.md template has hooks.pr.after_create" "after_create:" "$SETUP"
assert_contains "setup.md template has hooks.pr.after_merge" "after_merge:" "$SETUP"

# The YAML template must NOT contain the deprecated flat hooks.after_merge pattern
# (i.e., "after_merge:" should only appear under "pr:", not directly under "hooks:")
TOTAL=$((TOTAL + 1))
FLAT_HOOKS=$(echo "$SETUP_TEMPLATE" | grep -E '^  after_merge:' || true)
if [ -z "$FLAT_HOOKS" ]; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
    echo "FAIL: setup.md template has deprecated flat hooks.after_merge"
    echo "  expected: hooks.pr.after_merge (nested)"
    echo "  found: hooks.after_merge (flat)"
fi

# Setup questions should mention after_create hook point
assert_contains "setup.md questions mention after_create hook" "after_create" "$SETUP"

# ── Section: Build invariant integrity ───────────────────
# Build must never checkout/pull in the primary checkout; worktrees are
# based on origin/$DEFAULT_BRANCH after a refs-only fetch, and artifact
# ignoring goes through info/exclude instead of the primary's .gitignore.

echo ""
echo "=== Build invariant integrity ==="

assert_not_contains "build never checkouts/pulls the primary" 'git checkout $DEFAULT_BRANCH && git pull' "$BUILD_SKILL"
assert_contains "build ignores artifacts via info/exclude" "info/exclude" "$BUILD_SKILL"
assert_not_contains "build --on-branch avoids broken porcelain grep" 'grep -B1 "branch refs/heads' "$BUILD_SKILL"

# ── Section: Worktree naming contract ────────────────────
# Worktree dirs are the branch name with '/' flattened to '-' (declared in
# worktree-lifecycle.md). Raw branch names nest directories and break every
# single-level glob (status scans, crash recovery, tree-guard guidance).

echo ""
echo "=== Worktree naming contract ==="

LIFECYCLE="$PLUGIN_DIR/worktree-lifecycle.md"
RESPOND_SKILL="$PLUGIN_DIR/skills/respond/SKILL.md"

assert_contains "worktree-lifecycle declares the slug rule" "tr '/' '-'" "$LIFECYCLE"
assert_not_contains "respond does not address worktree dirs by raw branch name" "worktrees/<branch>" "$RESPOND_SKILL"
assert_not_contains "tree-guard does not point at raw-branch worktree path" 'worktrees/${CURRENT_BRANCH}' "$PLUGIN_DIR/hooks/tree-guard.sh"
assert_not_contains "worktree-lifecycle uses numbered respond state filename" "respond-state.md" "$LIFECYCLE"

# ── Section: State-file lifecycle ────────────────────────
# Every state file must have an owner that removes it — leftovers keep
# tree-guard armed against the branch indefinitely.

echo ""
echo "=== State-file lifecycle ==="

assert_contains "review finalize cleans up leftover respond state" "respond-state-{N}.md" "$PLUGIN_DIR/skills/review/SKILL.md"

STATUS_SKILL="$PLUGIN_DIR/skills/status/SKILL.md"

# status must know every artifact class the pipelines create.
assert_contains "status scans review worktrees" "review-worktrees" "$STATUS_SKILL"
assert_contains "status checks Worktree: references before calling a worktree orphaned" "Worktree:" "$STATUS_SKILL"
assert_contains "status clean handles respond-decisions files" "respond-decisions" "$STATUS_SKILL"
assert_not_contains "status counts nested subtasks in plans" "grep -c '^\- \[" "$STATUS_SKILL"

# ── Section: GitHub adapter template validity ────────────
# Known-bad command patterns that fail at runtime against real gh/jq.

echo ""
echo "=== GitHub adapter template validity ==="

GH_ADAPTER="$PLUGIN_DIR/adapters/github"

# jq string interpolation is \(...) — a double backslash reaches jq as a
# literal backslash and the expression outputs itself instead of the value.
for f in "$GH_ADAPTER"/*.md; do
    assert_not_contains "$(basename "$f") has no double-backslash jq interpolation" '\\(' "$f"
done

# gh api --field never parses JSON literals — arrays arrive as strings and
# the reviews endpoint rejects them with 422. Arrays must go via --input.
assert_not_contains "review.md does not pass comments array via --field" "--field 'comments=" "$GH_ADAPTER/review.md"

# gh pr checks --json has no conclusion/detailsUrl fields (bucket/link exist).
assert_not_contains "hosting.md does not use invalid gh pr checks field conclusion" "conclusion" "$GH_ADAPTER/hosting.md"
assert_not_contains "hosting.md does not use invalid gh pr checks field detailsUrl" "detailsUrl" "$GH_ADAPTER/hosting.md"

# gh's --jq flag takes a single expression string; it has no --arg option.
assert_not_contains "connection.md does not pass --arg to gh --jq" "--jq --arg" "$GH_ADAPTER/connection.md"

# ── Results ──────────────────────────────────────────────

echo ""
echo "════════════════════════════════════════"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo "════════════════════════════════════════"

[ "$FAIL" -eq 0 ] || exit 1
