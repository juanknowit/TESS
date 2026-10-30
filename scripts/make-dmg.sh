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
  python3 -m pip install --quiet --user "dmgbuild==1.6.7" 2>/dev/null \
    || python3 -m pip install --quiet --user --break-system-packages "dmgbuild==1.6.7"
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
  "$VOLUME" "$OUT"

hdiutil verify "$OUT" >/dev/null
echo "✓ $(basename "$OUT") ($(du -h "$OUT" | cut -f1 | xargs))"
