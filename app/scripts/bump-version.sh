#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

PART="${1:-patch}"
case "$PART" in
  patch|minor|major) ;;
  *) echo "usage: $0 [patch|minor|major]" >&2; exit 2 ;;
esac

. .githooks/version-lib.sh
FILE="$MWT_VERSION_FILE"

CURRENT="$(read_version < "$FILE")"
if ! is_semver "$CURRENT"; then
  echo "Could not read an X.Y.Z version from $FILE" >&2
  exit 1
fi

BASE="$(version_base)"

START="$CURRENT"
if [ -n "$BASE" ]; then
  BASE_VERSION="$(git show "$BASE:$FILE" 2>/dev/null | read_version || true)"
  if is_semver "$BASE_VERSION" && newer "$BASE_VERSION" "$CURRENT"; then
    START="$BASE_VERSION"
  fi
fi

IFS=. read -r MAJOR MINOR PATCH <<EOF
$START
EOF
MAJOR=$((10#$MAJOR))
MINOR=$((10#$MINOR))
PATCH=$((10#$PATCH))
case "$PART" in
  patch) PATCH=$((PATCH + 1)) ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
esac
NEW="$MAJOR.$MINOR.$PATCH"

sed "s/version = \"$CURRENT\"/version = \"$NEW\"/" "$FILE" > "$FILE.tmp"
mv "$FILE.tmp" "$FILE"
if [ "$(read_version < "$FILE")" != "$NEW" ]; then
  echo "Could not write version $NEW to $FILE" >&2
  exit 1
fi
echo "$CURRENT -> $NEW"
