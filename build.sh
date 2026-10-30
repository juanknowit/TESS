#!/bin/bash
# Builds TESS.app from source. Needs macOS 14+ and Xcode or the Command Line Tools (xcode-select --install).
#   ./build.sh                  build into ./build.noindex/TESS.app
#   ./build.sh --install        build, copy to /Applications and launch
#   ./build.sh --dev [--install]  build "TESS Dev" instead: a separate app (app.tess.assistant.dev) with its
#                               own settings, data, keychain item and permissions. Use it for local testing
#                               next to the TESS you download from GitHub; it never touches that TESS.
#
# Optional environment:
#   TESS_VERSION     version to stamp into the app, e.g. 0.9.0 or 0.9.0-beta (default: Info.plist)
#   TESS_BUILD       build number (default: Info.plist)
#   UNIVERSAL=1      build one app for both Apple silicon and Intel
#   SIGN_IDENTITY    certificate name or SHA-1 to sign with
#   SIGN_HARDENED=1  sign with the hardened runtime and a timestamp (needed for notarisation)
#   REQUIRE_SIGNING=1  fail instead of falling back to ad-hoc signing (used for releases)
set -euo pipefail
cd "$(dirname "$0")"

INSTALL=0
DEV=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --dev) DEV=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

# Everything that identifies the app. Release values are what TESS has always used; never change them.
if [ "$DEV" = 1 ]; then
  APP_NAME="TESS Dev"; EXEC_NAME="TESS Dev"; BUNDLE_ID="app.tess.assistant.dev"
  ICON="AppIconDev"; SUPPORT_FOLDER="TESS Dev"
else
  APP_NAME="TESS"; EXEC_NAME="TESS"; BUNDLE_ID="app.tess.assistant"
  ICON="AppIcon"; SUPPORT_FOLDER="TESS"
fi
echo "▸ Building $APP_NAME ($BUNDLE_ID)"

if [ -n "${UNIVERSAL:-}" ]; then
  # Release builds run on both Apple silicon and Intel Macs.
  echo "▸ Compiling for Apple silicon and Intel…"
  swift build -c release --arch arm64
  swift build -c release --arch x86_64
  BIN="$(mktemp -d)/TESS"
  lipo -create -output "$BIN" \
    "$(swift build -c release --arch arm64 --show-bin-path)/TESS" \
    "$(swift build -c release --arch x86_64 --show-bin-path)/TESS"
else
  echo "▸ Compiling…"
  swift build -c release
  BIN="$(swift build -c release --show-bin-path)/TESS"
fi

# ".noindex" keeps Spotlight and Launchpad from listing this build copy next to the installed app.
APP="build.noindex/$APP_NAME.app"
rm -rf build "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$EXEC_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "Resources/$ICON.icns" "$APP/Contents/Resources/$ICON.icns"

PLIST="$APP/Contents/Info.plist"
if [ "$DEV" = 1 ]; then
  plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$PLIST"
  plutil -replace CFBundleName -string "$APP_NAME" "$PLIST"
  plutil -replace CFBundleDisplayName -string "$APP_NAME" "$PLIST"
  plutil -replace CFBundleExecutable -string "$EXEC_NAME" "$PLIST"
  plutil -replace CFBundleIconFile -string "$ICON" "$PLIST"
  COMMIT="$(git rev-parse --short HEAD 2>/dev/null || true)"
  [ -n "$COMMIT" ] && [ -n "$(git status --porcelain 2>/dev/null)" ] && COMMIT="$COMMIT+changes"
  plutil -replace TESSCommit -string "${COMMIT:-unknown}" "$PLIST"
  # Every Dev build gets a new signature (as with any code change), so "permissions survive rebuilds"
  # is really exercised, not just an identical app being reinstalled.
  plutil -replace TESSBuiltAt -string "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$PLIST"
fi
# Never install something whose identity doesn't match what this script is about to replace.
if [ "$(plutil -extract CFBundleIdentifier raw "$PLIST")" != "$BUNDLE_ID" ]; then
  echo "✗ Built app has bundle ID $(plutil -extract CFBundleIdentifier raw "$PLIST"), expected $BUNDLE_ID" >&2
  exit 1
fi

# ── Version ────────────────────────────────────────────────────────────────────
if [ -n "${TESS_VERSION:-}" ]; then
  # CFBundleShortVersionString must be numeric (0.9.0); the full name (0.9.0 beta) is shown in About.
  plutil -replace CFBundleShortVersionString -string "${TESS_VERSION%%-*}" "$PLIST"
  plutil -replace TESSDisplayVersion -string "${TESS_VERSION//-/ }" "$PLIST"
  plutil -replace TESSVersion -string "$TESS_VERSION" "$PLIST"
fi
if [ -n "${TESS_BUILD:-}" ]; then
  plutil -replace CFBundleVersion -string "$TESS_BUILD" "$PLIST"
fi
echo "▸ Version $(plutil -extract CFBundleShortVersionString raw "$PLIST") ($(plutil -extract CFBundleVersion raw "$PLIST"))"

# ── Signing ────────────────────────────────────────────────────────────────────
# macOS remembers permissions (Screen Recording, Accessibility, Automation…) per code signature.
# Ad-hoc signatures change with every build, so permissions would reset after each rebuild.
# We therefore sign with a stable identity, in this order:
#   1. $SIGN_IDENTITY, if set
#   2. an "Apple Development" certificate, if you have one (Xcode signed in to an Apple ID)
#   3. a free, self-signed "TESS Local Signing" certificate created once in your login keychain
#   4. ad-hoc, as a last resort (and on CI)
CERT_NAME="TESS Local Signing"

create_local_identity() {
  echo "▸ Creating a local signing certificate \"$CERT_NAME\" (one time only)…"
  local tmp; tmp="$(mktemp -d)"
  cat > "$tmp/cert.cnf" <<CNF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $CERT_NAME
[ ext ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
  local pass="tess-$RANDOM-$RANDOM"
  /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$tmp/cert.cnf" \
    -keyout "$tmp/key.pem" -out "$tmp/cert.pem" >/dev/null 2>&1 &&
  /usr/bin/openssl pkcs12 -export -name "$CERT_NAME" -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
    -out "$tmp/identity.p12" -passout "pass:$pass" >/dev/null 2>&1 &&
  security import "$tmp/identity.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$pass" \
    -T /usr/bin/codesign >/dev/null
  local status=$?
  rm -rf "$tmp"
  return $status
}

IDENTITY="${SIGN_IDENTITY:-}"
RUNTIME=()
if [ -n "${SIGN_HARDENED:-}" ]; then
  RUNTIME=(--options runtime --timestamp --entitlements Resources/TESS.entitlements)
fi
if [ -z "$IDENTITY" ]; then
  DEV="$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 'Apple Development' | sed -E 's/.*"(.*)"/\1/' || true)"
  if [ -n "$DEV" ]; then
    IDENTITY="$DEV"
    RUNTIME=(--options runtime --entitlements Resources/TESS.entitlements)
  elif [ -z "${CI:-}" ]; then
    if ! security find-identity -p codesigning 2>/dev/null | grep -q "\"$CERT_NAME\""; then
      create_local_identity || echo "  (couldn't create it — falling back to ad-hoc signing)"
    fi
    if security find-identity -p codesigning 2>/dev/null | grep -q "\"$CERT_NAME\""; then
      IDENTITY="$CERT_NAME"
    fi
  fi
fi

SIGN_ERR="$(mktemp)"
if [ -n "$IDENTITY" ] && codesign --force ${RUNTIME[@]+"${RUNTIME[@]}"} --sign "$IDENTITY" "$APP" 2>"$SIGN_ERR"; then
  echo "▸ Signed with: $IDENTITY (permissions survive rebuilds)"
  SIGNED_AS="$IDENTITY"
elif [ -n "${REQUIRE_SIGNING:-}" ]; then
  echo "✗ Signing with \"${IDENTITY:-<none>}\" failed:" >&2
  cat "$SIGN_ERR" >&2
  exit 1
else
  [ -n "$IDENTITY" ] && echo "  (signing with \"$IDENTITY\" failed — using ad-hoc)"
  codesign --force --sign - "$APP"
  echo "▸ Signed ad-hoc (macOS may ask for permissions again after each rebuild)"
  SIGNED_AS="ad-hoc"
fi
rm -f "$SIGN_ERR"
codesign --verify --strict "$APP"

echo "✓ Built $APP"

if [ "$INSTALL" = 1 ]; then
  TARGET="/Applications/$APP_NAME.app"
  # Only ever touch this flavour: quit, reset and replace "$APP_NAME" ($BUNDLE_ID), nothing else.
  pkill -x "$EXEC_NAME" 2>/dev/null || true

  # The first time this app is installed with a new signing identity, clear the permissions macOS recorded
  # for the old one. Otherwise System Settings shows it switched on while the new build is still refused.
  MARKER="$HOME/Library/Application Support/$SUPPORT_FOLDER/signing-identity"
  if [ "$SIGNED_AS" != "ad-hoc" ] && [ "$(cat "$MARKER" 2>/dev/null)" != "$SIGNED_AS" ]; then
    echo "▸ New signing identity — resetting $APP_NAME's old macOS permissions so you can grant them once more"
    tccutil reset All "$BUNDLE_ID" >/dev/null 2>&1 || true
    mkdir -p "$(dirname "$MARKER")"
    printf '%s' "$SIGNED_AS" > "$MARKER"
  else
    echo "▸ Same signing identity as last time — $APP_NAME keeps its permissions"
  fi

  rm -rf "$TARGET"
  cp -R "$APP" /Applications/
  rm -rf build.noindex
  echo "✓ Installed to $TARGET (build copy removed)"
  open "$TARGET"
fi
