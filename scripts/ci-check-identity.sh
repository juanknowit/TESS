#!/bin/bash
# Checks that a built app has exactly the identity of its flavour.
#   scripts/ci-check-identity.sh release "build.noindex/TESS.app"
#   scripts/ci-check-identity.sh dev     "build.noindex/TESS Dev.app"
set -euo pipefail
FLAVOR="${1:?release or dev}"
APP="${2:?path to the .app}"
PLIST="$APP/Contents/Info.plist"
get() { plutil -extract "$1" raw "$PLIST" 2>/dev/null || echo "<missing>"; }

fail=0
expect() {  # key expected
  local actual; actual="$(get "$1")"
  if [ "$actual" = "$2" ]; then echo "  ✓ $1 = $2"; else echo "::error title=Identity ($FLAVOR)::$1 is \"$actual\", expected \"$2\""; fail=1; fi
}

echo "▸ Checking $FLAVOR identity of $APP"
if [ "$FLAVOR" = release ]; then
  expect CFBundleIdentifier app.tess.assistant
  expect CFBundleName TESS
  expect CFBundleExecutable TESS
  expect CFBundleIconFile AppIcon
  expect TESSCommit "<missing>"
else
  expect CFBundleIdentifier app.tess.assistant.dev
  expect CFBundleName "TESS Dev"
  expect CFBundleExecutable "TESS Dev"
  expect CFBundleIconFile AppIconDev
  [ "$(get TESSCommit)" != "<missing>" ] && echo "  ✓ TESSCommit = $(get TESSCommit)" || { echo "::error::TESSCommit missing"; fail=1; }
fi
EXEC="$APP/Contents/MacOS/$(get CFBundleExecutable)"
ICON="$APP/Contents/Resources/$(get CFBundleIconFile).icns"
[ -x "$EXEC" ] && echo "  ✓ executable present" || { echo "::error::missing executable $EXEC"; fail=1; }
[ -f "$ICON" ] && echo "  ✓ icon present" || { echo "::error::missing icon $ICON"; fail=1; }
SIGNED_ID="$(codesign -dv "$APP" 2>&1 | sed -n 's/^Identifier=//p')"
[ "$SIGNED_ID" = "$(get CFBundleIdentifier)" ] && echo "  ✓ signature identifier = $SIGNED_ID" \
  || { echo "::error::signature identifier \"$SIGNED_ID\" doesn't match the bundle ID"; fail=1; }
exit $fail
