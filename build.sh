#!/bin/bash
# Builds TESS.app from source. Needs macOS 14+ and Xcode or the Command Line Tools (xcode-select --install).
#   ./build.sh            build into ./build.noindex/TESS.app
#   ./build.sh --install  build, copy to /Applications and launch
set -euo pipefail
cd "$(dirname "$0")"

echo "▸ Compiling…"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/TESS"

# ".noindex" keeps Spotlight and Launchpad from listing this build copy next to the installed app.
APP="build.noindex/TESS.app"
rm -rf build "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TESS"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Sign with your Apple Development certificate if you have one (keeps macOS permissions across rebuilds),
# otherwise ad-hoc. Override with SIGN_IDENTITY="…".
IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 'Apple Development' | sed -E 's/.*"(.*)"/\1/' || true)"
fi
if [ -n "$IDENTITY" ]; then
  echo "▸ Signing with: $IDENTITY"
  codesign --force --options runtime --entitlements Resources/TESS.entitlements --sign "$IDENTITY" "$APP"
else
  echo "▸ Signing ad-hoc (macOS may ask for permissions again after each rebuild)"
  codesign --force --sign - "$APP"
fi

echo "✓ Built $APP"

if [ "${1:-}" = "--install" ]; then
  pkill -x TESS 2>/dev/null || true
  rm -rf /Applications/TESS.app
  cp -R "$APP" /Applications/
  rm -rf build.noindex
  echo "✓ Installed to /Applications/TESS.app (build copy removed)"
  open /Applications/TESS.app
fi
