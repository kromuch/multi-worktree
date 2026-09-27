#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

OUT="$(cd .. && pwd)/docs/images"
DEMO="${MWT_DEMO_ROOT:-/Users/Shared/mwt-demo}"
FEATURE="feature/gift-cards"
mkdir -p "$OUT"

capture_dmg=0
for arg in "$@"; do
  case "$arg" in
    --dmg) capture_dmg=1 ;;
    *) echo "usage: $0 [--dmg]" >&2; exit 2 ;;
  esac
done

swift build --product MultiWorktree
swift run MWTDemoSeed "$DEMO"
BIN="$PWD/.build/debug/MultiWorktree"
LOG="$PWD/.build/screenshot.log"

shoot() {
  local name="$1" screen="$2" appearance="$3" deps="$4"
  : > "$LOG"
  MWT_PREVIEW=1 MWT_CHROMELESS=1 MWT_HOME="$DEMO/home" MWT_SCREEN="$screen" \
    MWT_APPEARANCE="$appearance" MWT_DEPS="$deps" MWT_FEATURE="$FEATURE" "$BIN" > "$LOG" 2>&1 &
  local pid=$!
  local id=""
  for _ in $(seq 1 40); do
    id="$(sed -n 's/^MWT_WINDOW_ID=//p' "$LOG" | head -n 1)"
    [ -n "$id" ] && break
    sleep 0.25
  done
  if [ -z "$id" ]; then
    kill "$pid" 2>/dev/null || true
    cat "$LOG" >&2
    echo "no preview window for $name ($appearance)" >&2
    exit 1
  fi
  sleep 2
  screencapture -x -l "$id" "$OUT/$name-$appearance.png"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  echo "$OUT/$name-$appearance.png"
}

for appearance in light dark; do
  shoot home home "$appearance" ok
  shoot edit-group editGroup "$appearance" ok
  shoot spin-up spinUp "$appearance" ok
  shoot report report "$appearance" ok
  shoot tear-down tearDown "$appearance" ok
  shoot banner home "$appearance" noclaude
done

if [ ! -f .build/MultiWorktree.app/Contents/Resources/AppIcon.icns ]; then scripts/build-app.sh >/dev/null; fi
sips -s format png -Z 256 .build/MultiWorktree.app/Contents/Resources/AppIcon.icns --out "$OUT/icon.png" >/dev/null
echo "$OUT/icon.png"

if [ "$capture_dmg" = 1 ]; then
  VERSION="$(sed -n 's/.*version = "\(.*\)".*/\1/p' Sources/MWTKit/KitInfo.swift)"
  DMG="$PWD/.build/dist/MultiWorktree-$VERSION.dmg"
  if [ ! -f "$DMG" ]; then echo "run scripts/make-dmg.sh first" >&2; exit 1; fi
  if [ -d /Volumes/MultiWorktree ]; then echo "/Volumes/MultiWorktree is already mounted; eject it first." >&2; exit 1; fi
  hdiutil attach "$DMG" -noverify -noautoopen >/dev/null
  osascript -e 'tell application "Finder" to open disk "MultiWorktree"' >/dev/null
  sleep 2
  id="$(swift scripts/window-id.swift Finder MultiWorktree)"
  screencapture -x -l "$id" "$OUT/dmg.png"
  osascript -e 'tell application "Finder" to close (every window whose name is "MultiWorktree")' >/dev/null || true
  hdiutil detach /Volumes/MultiWorktree >/dev/null
  echo "$OUT/dmg.png"
fi
