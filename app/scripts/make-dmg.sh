#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

VOLUME=MultiWorktree
MOUNT="/Volumes/$VOLUME"
if [ -d "$MOUNT" ]; then
  echo "$MOUNT is already mounted; eject it first." >&2
  exit 1
fi

scripts/build-app.sh

VERSION="$(sed -n 's/.*version = "\(.*\)".*/\1/p' Sources/MWTKit/KitInfo.swift)"
APP="$PWD/.build/MultiWorktree.app"
DIST="$PWD/.build/dist"
WORK="$PWD/.build/dmg-work"
STAGE="$WORK/stage"
RW="$WORK/rw.dmg"
DMG="$DIST/MultiWorktree-$VERSION.dmg"

if [ -d "$WORK" ]; then find "$WORK" -delete; fi
mkdir -p "$STAGE/.background" "$DIST"
if [ -f "$DMG" ]; then find "$DMG" -delete; fi

swift scripts/dmg-background.swift "$WORK"
tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" -out "$STAGE/.background/background.tiff" >/dev/null
ditto "$APP" "$STAGE/MultiWorktree.app"
ln -s /Applications "$STAGE/Applications"

SIZE_MB=$(( $(du -sm "$STAGE" | cut -f1) + 20 ))
hdiutil create -volname "$VOLUME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -size "${SIZE_MB}m" -ov "$RW" >/dev/null
hdiutil attach "$RW" -readwrite -noverify -noautoopen >/dev/null

xcrun SetFile -a V "$MOUNT/.background"

cat > "$WORK/layout.applescript" <<'APPLESCRIPT'
on run argv
  set volumeName to item 1 of argv
  with timeout of 60 seconds
    tell application "Finder"
      tell disk volumeName
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 840, 548}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set text size of viewOptions to 13
        set background picture of viewOptions to file ".background:background.tiff"
        set position of item "MultiWorktree.app" of container window to {160, 190}
        set position of item "Applications" of container window to {480, 190}
        try
          set position of item ".background" of container window to {900, 190}
        end try
        update without registering applications
        delay 1
        close
      end tell
    end tell
  end timeout
end run
APPLESCRIPT

osascript "$WORK/layout.applescript" "$VOLUME" &
osascript_pid=$!
( sleep 90; kill "$osascript_pid" 2>/dev/null ) &
watchdog_pid=$!
layout_status=0
wait "$osascript_pid" || layout_status=$?
kill "$watchdog_pid" 2>/dev/null || true
wait "$watchdog_pid" 2>/dev/null || true

for _ in $(seq 1 20); do
  [ -f "$MOUNT/.DS_Store" ] && break
  sleep 0.5
done
if [ "$layout_status" -ne 0 ] || [ ! -f "$MOUNT/.DS_Store" ]; then
  echo "warning: Finder layout skipped (osascript status $layout_status); the DMG keeps Finder's default layout." >&2
fi

cp "$APP/Contents/Resources/AppIcon.icns" "$MOUNT/.VolumeIcon.icns"
xcrun SetFile -a C "$MOUNT"

if [ -d "$MOUNT/.fseventsd" ]; then find "$MOUNT/.fseventsd" -delete 2>/dev/null || true; fi
sync
for attempt in 1 2 3; do
  if hdiutil detach "$MOUNT" >/dev/null 2>&1; then break; fi
  if [ "$attempt" = 3 ]; then hdiutil detach "$MOUNT" -force >/dev/null; fi
  sleep 2
done

hdiutil convert "$RW" -format ULFO -o "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null
(cd "$DIST" && shasum -a 256 "MultiWorktree-$VERSION.dmg" > "MultiWorktree-$VERSION.dmg.sha256")
echo "$DMG"
