#!/bin/zsh
# Builds NowPlayingChip.app (no Xcode project needed) and ad-hoc signs it.
set -euo pipefail
cd "$(dirname "$0")"
APP=build/NowPlayingChip.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -swift-version 5 -target arm64-apple-macosx13.0 Sources/*.swift -o "$APP/Contents/MacOS/NowPlayingChip" 2>&1 || \
swiftc -O -swift-version 5 Sources/*.swift -o "$APP/Contents/MacOS/NowPlayingChip"
cp Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
# Bundle local config (client ID, playlist name) if present. Nothing secret is required.
[ -f .env ] && cp .env "$APP/Contents/Resources/.env"
# Prefer a stable self-signed cert so macOS keeps Automation permissions across rebuilds.
IDENTITY="${SIGN_IDENTITY:-NowPlayingChip}"
if security find-identity -p codesigning | grep -q "$IDENTITY"; then
  codesign --force --sign "$IDENTITY" "$APP"
else
  echo "Cert '$IDENTITY' not found — using ad-hoc signing (permissions will re-prompt each build)"
  codesign --force --sign - "$APP"
fi
echo "Built $APP — run with: open $APP"
