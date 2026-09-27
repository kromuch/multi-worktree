#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

open_after=0
install_after=0
for arg in "$@"; do
  case "$arg" in
    --open) open_after=1 ;;
    --install) install_after=1 ;;
    *) echo "usage: $0 [--open] [--install]" >&2; exit 2 ;;
  esac
done

if ! xcrun --find actool >/dev/null 2>&1; then
  echo "Full Xcode 27 or newer is required: install it and run sudo xcode-select -s /Applications/Xcode.app" >&2
  exit 1
fi

VERSION="$(sed -n 's/.*version = "\(.*\)".*/\1/p' Sources/MWTKit/KitInfo.swift)"
if [ -z "$VERSION" ]; then
  echo "Could not read the version from Sources/MWTKit/KitInfo.swift" >&2
  exit 1
fi
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

ARCH_FLAGS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCH_FLAGS[@]}" --product MultiWorktree
BIN="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)/MultiWorktree"
ARCHS="$(lipo -archs "$BIN")"
for want in arm64 x86_64; do
  case " $ARCHS " in
    *" $want "*) ;;
    *) echo "expected a universal binary with arm64 and x86_64, got: $ARCHS" >&2; exit 1 ;;
  esac
done

APP="$PWD/.build/MultiWorktree.app"
RESOURCES="$APP/Contents/Resources"
ACTOOL_LOG="$PWD/.build/actool.log"
if [ -d "$APP" ]; then find "$APP" -delete; fi
mkdir -p "$APP/Contents/MacOS" "$RESOURCES"
cp "$BIN" "$APP/Contents/MacOS/MultiWorktree"

if ! xcrun actool Resources/AppIcon.icon --compile "$RESOURCES" \
    --output-format human-readable-text --notices --warnings --errors \
    --output-partial-info-plist "$PWD/.build/icon-partial.plist" \
    --app-icon AppIcon --include-all-app-icons \
    --target-device mac --minimum-deployment-target 26.0 --platform macosx > "$ACTOOL_LOG" 2>&1; then
  cat "$ACTOOL_LOG" >&2
  exit 1
fi
if [ ! -f "$RESOURCES/Assets.car" ] || [ ! -f "$RESOURCES/AppIcon.icns" ]; then
  cat "$ACTOOL_LOG" >&2
  echo "actool did not produce Assets.car and AppIcon.icns" >&2
  exit 1
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>MultiWorktree</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>dev.kromuch.MultiWorktree</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>MultiWorktree</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>© 2026 kromuch. Licensed under AGPL-3.0.</string>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null

codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict --verbose=2 "$APP"

if [ "$install_after" = 1 ]; then
  pkill -x MultiWorktree || true
  DEST=/Applications/MultiWorktree.app
  if [ -d "$DEST" ]; then find "$DEST" -delete; fi
  ditto "$APP" "$DEST"
  open "$DEST"
  echo "Installed $DEST"
elif [ "$open_after" = 1 ]; then
  open "$APP"
fi
echo "$APP"
