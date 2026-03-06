#!/bin/bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
PLUGIN_JSON="$REPO_ROOT/plugins/flowyeah/.claude-plugin/plugin.json"
MARKETPLACE_JSON="$REPO_ROOT/.claude-plugin/marketplace.json"

CURRENT=$(grep -oP '"version":\s*"\K[^"]+' "$PLUGIN_JSON" | head -1)

if [ -z "$CURRENT" ]; then
  echo "bump-version: could not read version from $PLUGIN_JSON" >&2
  exit 1
fi

MAJOR="${CURRENT%%.*}"
REST="${CURRENT#*.}"
MINOR="${REST%%.*}"
PATCH="${REST#*.}"
NEW_VERSION="$MAJOR.$MINOR.$((PATCH + 1))"

sed -i "s/\"version\": \"$CURRENT\"/\"version\": \"$NEW_VERSION\"/g" \
  "$PLUGIN_JSON" "$MARKETPLACE_JSON"

git add "$PLUGIN_JSON" "$MARKETPLACE_JSON"

echo "bump-version: $CURRENT -> $NEW_VERSION"
