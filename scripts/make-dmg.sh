#!/bin/bash
# Packs TESS.app into a drag-to-install disk image.
#   scripts/make-dmg.sh build.noindex/TESS.app dist/TESS-0.9.0-beta.dmg
# Needs macOS and Python 3; installs dmgbuild with pip if it's missing.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:?usage: make-dmg.sh path/to/TESS.app output.dmg}"
OUT="${2:?usage: make-dmg.sh path/to/TESS.app output.dmg}"
VOLUME="${3:-TESS}"

if ! python3 -c "import dmgbuild" 2>/dev/null; then
  echo "▸ Installing dmgbuild…"
  # pip picks the newest release that supports this Python (the Command Line Tools ship 3.9).
  PIP=(python3 -m pip install --quiet --user "dmgbuild>=1.6.2,<1.7")
  if ! "${PIP[@]}"; then
    "${PIP[@]}" --break-system-packages   # Homebrew/externally managed Pythons
  fi
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# One TIFF holding both resolutions, so the window looks sharp on Retina screens.
tiffutil -cathidpicheck Resources/dmg/background.png Resources/dmg/background@2x.png \
  -out "$TMP/background.tiff" >/dev/null

mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
echo "▸ Building $(basename "$OUT")…"
python3 -m dmgbuild -s scripts/dmg-settings.py \
  -D app="$APP" \
  -D background="$TMP/background.tiff" \
  -D volume_icon="Resources/AppIcon.icns" \
  -D format=UDRW \
  "$VOLUME" "$TMP/installer.dmg"

# Give the window a navy background colour behind the picture, so Finder draws the names in white.
MOUNT="$(hdiutil attach "$TMP/installer.dmg" -nobrowse -noautoopen -plist \
  | python3 -c 'import plistlib,sys; print(next(e["mount-point"] for e in plistlib.loads(sys.stdin.buffer.read())["system-entities"] if "mount-point" in e))')"
python3 scripts/dmg-label-color.py "$MOUNT/.DS_Store"
rm -rf "$MOUNT/.fseventsd"
hdiutil detach "$MOUNT" -quiet || hdiutil detach "$MOUNT" -force -quiet

hdiutil convert "$TMP/installer.dmg" -format ULFO -o "$OUT" -quiet

hdiutil verify "$OUT" >/dev/null
echo "✓ $(basename "$OUT") ($(du -h "$OUT" | cut -f1 | xargs))"
