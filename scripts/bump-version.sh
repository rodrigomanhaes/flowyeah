#!/bin/bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
PLUGIN_JSON="$REPO_ROOT/plugins/flowyeah/.claude-plugin/plugin.json"
MARKETPLACE_JSON="$REPO_ROOT/.claude-plugin/marketplace.json"
PLUGIN_REL="plugins/flowyeah/.claude-plugin/plugin.json"

read_version() {
  sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' | head -1
}

CURRENT=$(read_version < "$PLUGIN_JSON")

if [ -z "$CURRENT" ]; then
  echo "bump-version: could not read version from $PLUGIN_JSON" >&2
  exit 1
fi

# A failed commit attempt leaves the bump staged; re-running must not bump
# again. If the index already carries a version different from HEAD's, the
# bump for this commit attempt is done (this also respects a manually staged
# version change).
if git rev-parse -q --verify HEAD >/dev/null 2>&1; then
  HEAD_VERSION=$(git -C "$REPO_ROOT" show "HEAD:$PLUGIN_REL" 2>/dev/null | read_version || true)
  INDEX_VERSION=$(git -C "$REPO_ROOT" show ":$PLUGIN_REL" 2>/dev/null | read_version || true)
  if [ -n "$HEAD_VERSION" ] && [ -n "$INDEX_VERSION" ] && [ "$INDEX_VERSION" != "$HEAD_VERSION" ]; then
    echo "bump-version: version already staged at $INDEX_VERSION (HEAD has $HEAD_VERSION) — not bumping again"
    exit 0
  fi
fi

# Refuse to bump over drifted manifests: sed only rewrites exact matches of
# $CURRENT, so a diverged marketplace.json would silently stay behind.
MISMATCH=$(grep -o '"version": *"[^"]*"' "$MARKETPLACE_JSON" | sed 's/.*"\(.*\)"/\1/' | grep -vxF "$CURRENT" || true)
if [ -n "$MISMATCH" ]; then
  echo "bump-version: marketplace.json has version(s) [$(printf '%s' "$MISMATCH" | tr '\n' ' ')] but plugin.json has $CURRENT — fix the drift before committing" >&2
  exit 1
fi

MAJOR="${CURRENT%%.*}"
REST="${CURRENT#*.}"
MINOR="${REST%%.*}"
PATCH="${REST#*.}"

case "$PATCH" in
  ''|*[!0-9]*)
    echo "bump-version: patch segment '$PATCH' of $CURRENT is not numeric — bump manually" >&2
    exit 1
    ;;
esac

NEW_VERSION="$MAJOR.$MINOR.$((PATCH + 1))"

sed -i "s/\"version\": \"$CURRENT\"/\"version\": \"$NEW_VERSION\"/g" \
  "$PLUGIN_JSON" "$MARKETPLACE_JSON"

# Verify both files were actually rewritten before letting the commit proceed.
PLUGIN_COUNT=$(grep -c "\"version\": \"$NEW_VERSION\"" "$PLUGIN_JSON" || true)
MARKET_COUNT=$(grep -c "\"version\": \"$NEW_VERSION\"" "$MARKETPLACE_JSON" || true)
if [ "${PLUGIN_COUNT:-0}" -ne 1 ] || [ "${MARKET_COUNT:-0}" -ne 2 ]; then
  echo "bump-version: rewrite verification failed — expected 1 occurrence of $NEW_VERSION in plugin.json and 2 in marketplace.json, got ${PLUGIN_COUNT:-0}/${MARKET_COUNT:-0}" >&2
  exit 1
fi

git add "$PLUGIN_JSON" "$MARKETPLACE_JSON"

echo "bump-version: $CURRENT -> $NEW_VERSION"
