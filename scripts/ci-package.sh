#!/bin/bash
# CI: builds TESS.app and packs dist/TESS-<version>.dmg, .zip and SHA256SUMS.txt.
# Uses TESS_VERSION/TESS_BUILD (scripts/ci-version.sh) and any SIGN_* settings
# (scripts/ci-import-certificate.sh). With NOTARIZE=1 the installer is notarised and stapled.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${TESS_VERSION:?run scripts/ci-version.sh first}"

if ! ./build.sh 2>&1 | tee build.log; then
  # Surface compiler errors as annotations on the run.
  grep -E "error:" build.log | sed -E 's/\x1b\[[0-9;]*m//g' | sort -u | head -40 | while IFS= read -r line; do
    echo "::error::${line}"
  done
  exit 1
fi
lipo -archs build.noindex/TESS.app/Contents/MacOS/TESS
codesign -dv build.noindex/TESS.app 2>&1 | grep -E "^(Identifier|Authority|Signature|TeamIdentifier|Runtime)" || true

DMG="dist/TESS-$TESS_VERSION.dmg"
scripts/make-dmg.sh build.noindex/TESS.app "$DMG" "TESS ${TESS_VERSION//-/ }"

if [ -n "${NOTARIZE:-}" ]; then
  : "${APPLE_ID:?}" "${APPLE_TEAM_ID:?}" "${APPLE_APP_PASSWORD:?}"
  codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG"
  xcrun notarytool submit "$DMG" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_PASSWORD" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler staple build.noindex/TESS.app
fi

# ditto keeps the bundle's permissions and structure intact.
ditto -c -k --keepParent build.noindex/TESS.app "dist/TESS-$TESS_VERSION.zip"
(cd dist && shasum -a 256 *.dmg *.zip > SHA256SUMS.txt && cat SHA256SUMS.txt && ls -lh)
