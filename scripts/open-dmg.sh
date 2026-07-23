#!/bin/bash
# Optional: open MetaBurn.dmg exactly once with the locked Finder layout.
# Default rebuild policy (Apps/AGENTS.md): copy DMG to Desktop and STOP — do NOT call
# this unless the user explicitly asks to open/mount the DMG.
# Avoids the double-window bug from `open foo.dmg` + AppleScript `open disk`.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/.."
VERSION="$(sed -n 's/.*"version".*"\([^"]*\)".*/\1/p' "$PROJECT_DIR/Sources/MetaBurn/Resources/version.json")"
VOLUME_NAME="MetaBurn ${VERSION}"
DMG_PATH="${1:-$HOME/Desktop/MetaBurn.dmg}"
LAUNCH_APP="${LAUNCH_APP:-1}"

if [ ! -f "$DMG_PATH" ]; then
  echo "DMG not found: $DMG_PATH" >&2
  exit 1
fi

# Close any existing MetaBurn mounts (Desktop copy or build/Release copy).
for vol in "/Volumes/${VOLUME_NAME}" "/Volumes/MetaBurn"; do
  if [ -d "$vol" ]; then
    hdiutil detach "$vol" -force -quiet 2>/dev/null || true
  fi
done

# Mount without auto-opening Finder (-nobrowse).
hdiutil attach "$DMG_PATH" -nobrowse -noverify -quiet

# Single Finder window + locked layout.
osascript <<APPLESCRIPT
tell application "Finder"
  set volName to "${VOLUME_NAME}"
  if not (exists disk volName) then return
  -- One window only
  open disk volName
  set w to container window of disk volName
  set toolbar visible of w to false
  set statusbar visible of w to false
  try
    set pathbar visible of w to false
  end try
  set sidebar width of w to 0
  set current view of w to icon view
  -- Locked 500×420 at (440, 240)
  set the bounds of w to {440, 240, 940, 660}
  set icon size of icon view options of w to 128
  set arrangement of icon view options of w to not arranged
  activate
end tell
APPLESCRIPT

if [ "$LAUNCH_APP" = "1" ] && [ -d "/Volumes/${VOLUME_NAME}/MetaBurn.app" ]; then
  open "/Volumes/${VOLUME_NAME}/MetaBurn.app"
fi

echo "Opened once: $DMG_PATH → volume '${VOLUME_NAME}'"
