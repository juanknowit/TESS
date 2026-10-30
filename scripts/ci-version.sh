#!/bin/bash
# CI: works out the version for this run and exports TESS_VERSION, TESS_BUILD, RELEASE_TAG, RELEASE_NAME.
#   RELEASE_INPUT  version typed into "Run workflow" (may be empty)
#   IS_RELEASE     "true" for release runs (a v* tag, or RELEASE_INPUT set)
set -euo pipefail
cd "$(dirname "$0")/.."

PLIST_VERSION="$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)"
if [ -n "${RELEASE_INPUT:-}" ]; then
  VERSION="${RELEASE_INPUT#v}"
  if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]]; then
    echo "::error title=Version::\"$RELEASE_INPUT\" isn't a version like 0.9.0-beta or 1.0.0"
    exit 1
  fi
  if git ls-remote --exit-code --tags origin "refs/tags/v$VERSION" >/dev/null; then
    echo "::error title=Version::v$VERSION has already been released"
    exit 1
  fi
elif [ "${IS_RELEASE:-}" = true ]; then
  VERSION="${GITHUB_REF_NAME#v}"
else
  VERSION="$PLIST_VERSION-dev.$GITHUB_RUN_NUMBER"
fi
if [ "${IS_RELEASE:-}" = true ] && [ "${VERSION%%-*}" != "$PLIST_VERSION" ]; then
  echo "::warning title=Version::Version $VERSION doesn't match Info.plist ($PLIST_VERSION); the app will say ${VERSION%%-*}."
fi

{
  echo "RELEASE_TAG=v$VERSION"
  echo "TESS_VERSION=$VERSION"
  echo "TESS_BUILD=$GITHUB_RUN_NUMBER"
  echo "RELEASE_NAME=TESS ${VERSION//-/ }"
} >> "$GITHUB_ENV"
echo "::notice title=Version::$VERSION (build $GITHUB_RUN_NUMBER)"
