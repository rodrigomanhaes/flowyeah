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
    assert_file_exists "adapter $name has connection.md" "$dir/connection.md"
done

for dir in "$PLUGIN_DIR"/skills/*/; do
    name="$(basename "$dir")"
    assert_file_exists "skill $name has SKILL.md" "$dir/SKILL.md"
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
    # Skip schema-free adapter keys (contain '<')
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
# Lines like: ├── gitlab/  or └── newrelic/
# Use sed to extract the adapter directory name.
tree_adapters="$(grep -E '(├── |└── )[a-z]+/' "$BUILD_SKILL" | sed 's/.*[├└]── //; s/\/.*//' | sort -u)"

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

# ── Results ──────────────────────────────────────────────

echo ""
echo "════════════════════════════════════════"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo "════════════════════════════════════════"

[ "$FAIL" -eq 0 ] || exit 1
