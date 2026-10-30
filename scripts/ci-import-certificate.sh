#!/bin/bash
# CI only: imports a code-signing certificate into a temporary keychain and tells later steps to use it.
#   scripts/ci-import-certificate.sh TESS_SIGNING   # reads $TESS_SIGNING_P12 (base64) and $TESS_SIGNING_PASSWORD
set -euo pipefail

PREFIX="${1:?usage: ci-import-certificate.sh SECRET_PREFIX}"
P12_VAR="${PREFIX}_P12"
PASS_VAR="${PREFIX}_PASSWORD"
P12_B64="${!P12_VAR:?missing \$$P12_VAR}"
P12_PASS="${!PASS_VAR:-}"

TMP="${RUNNER_TEMP:-$(mktemp -d)}"
KEYCHAIN="$TMP/tess-signing.keychain-db"
KEYCHAIN_PASS="$(uuidgen)"

security create-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"

printf '%s' "$P12_B64" | base64 --decode > "$TMP/certificate.p12"
security import "$TMP/certificate.p12" -k "$KEYCHAIN" -P "$P12_PASS" -T /usr/bin/codesign >/dev/null
rm -f "$TMP/certificate.p12"

# Let codesign use the key without a prompt, and put the keychain on the search list.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASS" "$KEYCHAIN" >/dev/null
security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')

# Sign by SHA-1 so the identity is unambiguous. (-v is not used: self-signed certificates aren't "valid".)
LINE="$(security find-identity -p codesigning "$KEYCHAIN" | grep -m1 -E '^ *[0-9]+\) [0-9A-F]{40} ')"
HASH="$(echo "$LINE" | awk '{print $2}')"
NAME="$(echo "$LINE" | sed -E 's/.*"(.*)".*/\1/')"
[ -n "$HASH" ] || { echo "::error::No code-signing identity found in $P12_VAR"; exit 1; }

{
  echo "SIGN_IDENTITY=$HASH"
  echo "SIGN_NAME=$NAME"
  echo "SIGN_KEYCHAIN=$KEYCHAIN"
  echo "REQUIRE_SIGNING=1"
} >> "${GITHUB_ENV:-/dev/null}"
echo "::notice title=Signing::Signing with \"$NAME\" (${HASH:0:8}…)"
