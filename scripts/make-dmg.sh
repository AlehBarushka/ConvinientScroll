#!/usr/bin/env bash
# Builds a Release MacToolkit.app and packs it into dist/MacToolkit-<version>.dmg,
# a disk image whose window shows the app next to an Applications link to drag it onto.
#
# Needs create-dmg (brew install create-dmg). create-dmg lays the window out through Finder,
# so run it from a logged-in desktop session; macOS may ask to allow controlling Finder.
# The background comes from dmg/ (see scripts/render-dmg-background.swift).
set -euo pipefail

# The Xcode project and scheme keep the original name; the product was renamed to Mac Toolkit.
PROJECT_NAME="ConvinientScroll"
APP_NAME="MacToolkit"
VOLUME_NAME="Mac Toolkit"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"

# Window and icon geometry, in points. Keep in sync with scripts/render-dmg-background.swift.
# Finder window bounds include the title bar (32 on macOS 26, 28 on earlier versions); icon
# positions are measured from the top left of the content area below it.
CONTENT_WIDTH=540
CONTENT_HEIGHT=380
TITLE_BAR=32
WINDOW_WIDTH=$CONTENT_WIDTH
WINDOW_HEIGHT=$((CONTENT_HEIGHT + TITLE_BAR))
ICON_SIZE=128
APP_X=140
DROP_X=400
ICON_Y=190

fail() {
  echo "error: $*" >&2
  exit 1
}

# Prints "<width>, <height>" of the window size Finder stored in the mounted volume's .DS_Store
# (a "{{x, y}, {width, height}}" string).
stored_window_size() {
  grep -a -o -E '\{\{[0-9]+, [0-9]+\}, \{[0-9]+, [0-9]+\}\}' "/Volumes/$VOLUME_NAME/.DS_Store" |
    head -n 1 |
    sed -E 's/.*\}, \{([0-9]+, [0-9]+)\}\}/\1/'
}

# create-dmg ejects the image before Finder has written the final window bounds, so on recent
# macOS the window opens at Finder's default size instead of $WINDOW_WIDTH x $WINDOW_HEIGHT.
# Set the bounds again on a writable copy, let Finder flush them while the volume is unmounted,
# read back what was stored, and only then recompress the image.
fix_window_bounds() {
  local image="$1" writable="$WORK/layout.dmg" attempt stored
  hdiutil convert "$image" -format UDRW -o "$writable" -quiet

  for attempt in 1 2 3; do
    hdiutil attach "$writable" -noautoopen -quiet
    osascript - "$VOLUME_NAME" 200 120 $((200 + WINDOW_WIDTH)) $((120 + WINDOW_HEIGHT)) <<'APPLESCRIPT'
on run argv
  tell application "Finder"
    tell disk (item 1 of argv)
      open
      delay 1
      set bounds of container window to {(item 2 of argv) as integer, (item 3 of argv) as integer, (item 4 of argv) as integer, (item 5 of argv) as integer}
      -- With "show hidden files" on, Finder lists these. create-dmg parks them just right of
      -- the window, where an enlarged window shows them; move them far beyond the background.
      repeat with hiddenName in {".background", ".VolumeIcon.icns"}
        try
          set position of item hiddenName to {4000, 100}
        end try
      end repeat
      delay 1
      close
    end tell
  end tell
end run
APPLESCRIPT
    sleep 3
    rm -rf "/Volumes/$VOLUME_NAME/.fseventsd"
    hdiutil detach "/Volumes/$VOLUME_NAME" -quiet || hdiutil detach "/Volumes/$VOLUME_NAME" -force -quiet

    hdiutil attach "$writable" -readonly -nobrowse -noautoopen -quiet
    stored="$(stored_window_size || true)"
    hdiutil detach "/Volumes/$VOLUME_NAME" -quiet || hdiutil detach "/Volumes/$VOLUME_NAME" -force -quiet

    if [ "$stored" = "$WINDOW_WIDTH, $WINDOW_HEIGHT" ]; then
      hdiutil convert "$writable" -format UDZO -imagekey zlib-level=9 -o "$image" -ov -quiet
      return 0
    fi
    echo "window size stored as '${stored:-nothing}' (attempt $attempt of 3), retrying" >&2
  done
  fail "Finder did not store the $WINDOW_WIDTH x $WINDOW_HEIGHT window size"
}

command -v create-dmg >/dev/null || fail "create-dmg not found. Install it with: brew install create-dmg"

# A leftover mount makes create-dmg name the new volume "$VOLUME_NAME 1" and the layout goes wrong.
[ ! -e "/Volumes/$VOLUME_NAME" ] || fail "/Volumes/$VOLUME_NAME is already mounted. Eject it and run again."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Without stripping, the executable carries the debug map with the absolute paths of the build
# machine (/Users/<name>/...), which would end up in a public release.
echo "==> Building Release"
xcodebuild \
  -project "$ROOT/$PROJECT_NAME.xcodeproj" \
  -scheme "$PROJECT_NAME" \
  -configuration Release \
  -derivedDataPath "$WORK/build" \
  -quiet \
  DEPLOYMENT_POSTPROCESSING=YES \
  STRIP_INSTALLED_PRODUCT=YES \
  COPY_PHASE_STRIP=YES \
  STRIP_STYLE=debugging \
  build

APP="$WORK/build/Build/Products/Release/$APP_NAME.app"
[ -d "$APP" ] || fail "build did not produce $APP"

# Refuse to publish an executable that still carries the local home directory.
if LC_ALL=C grep -a -F -q "$HOME" "$APP/Contents/MacOS/$APP_NAME"; then
  fail "the built executable contains $HOME; debug information was not stripped"
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[ -n "$VERSION" ] || fail "cannot read the app version from Info.plist"
ICON="$APP/Contents/Resources/AppIcon.icns"
[ -f "$ICON" ] || fail "built app has no AppIcon.icns"

# One TIFF holding both the 1x and the 2x picture, so the window is sharp on Retina displays.
tiffutil -cathidpicheck "$ROOT/dmg/background.png" "$ROOT/dmg/background@2x.png" \
  -out "$WORK/background.tiff" >/dev/null

mkdir "$WORK/stage"
cp -R "$APP" "$WORK/stage/"

OUTPUT="$DIST/$APP_NAME-$VERSION.dmg"
mkdir -p "$DIST"
rm -f "$OUTPUT"

echo "==> Creating $OUTPUT"
create-dmg \
  --volname "$VOLUME_NAME" \
  --volicon "$ICON" \
  --background "$WORK/background.tiff" \
  --window-pos 200 120 \
  --window-size "$WINDOW_WIDTH" "$WINDOW_HEIGHT" \
  --icon-size "$ICON_SIZE" \
  --icon "$APP_NAME.app" "$APP_X" "$ICON_Y" \
  --hide-extension "$APP_NAME.app" \
  --app-drop-link "$DROP_X" "$ICON_Y" \
  "$OUTPUT" \
  "$WORK/stage"

echo "==> Fixing the stored window size"
fix_window_bounds "$OUTPUT"

echo "==> Done: $OUTPUT"
