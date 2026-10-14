#!/usr/bin/env bash
# Sonoma (macOS 14): install and select Xcode 16.x via xcodes.
set -euo pipefail

if ! command -v xcodes >/dev/null 2>&1; then
  echo "Install xcodes: brew install xcodesorg/made/xcodes"
  exit 1
fi

echo "Installed Xcode apps:"
ls /Applications | grep -i '^Xcode' || true

echo "Available Xcode 16 releases (xcodes list):"
xcodes list | grep '^16\.' || true

TARGET="${1:-16.4}"
echo "Installing Xcode $TARGET (requires Apple ID / 2FA — human step)..."
xcodes install "$TARGET" --experimental-unxip

APP="/Applications/Xcode-${TARGET}.app"
if [[ ! -d "$APP" ]]; then
  APP="/Applications/Xcode.app"
fi

echo "Select developer dir (may require sudo):"
echo "  sudo xcode-select -s $APP/Contents/Developer"
echo "  sudo xcodebuild -license accept"
echo "  xcodebuild -runFirstLaunch"
