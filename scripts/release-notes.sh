#!/bin/bash
# Prints the GitHub release notes for a version: its CHANGELOG section plus install instructions.
#   scripts/release-notes.sh 0.9.0-beta
#   NOTARIZED=1 scripts/release-notes.sh 1.0.0
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: release-notes.sh VERSION}"
DMG="TESS-$VERSION.dmg"

SECTION="$(awk -v head="## [$VERSION]" '
  index($0, head) == 1 { on = 1; next }
  on && /^## \[/       { exit }
  on && /^\[[^]]+\]: /  { next }
  on                   { print }
' CHANGELOG.md)"

if [ -z "${SECTION//[[:space:]]/}" ]; then
  echo "CHANGELOG.md has no section for [$VERSION]" >&2
  exit 1
fi

printf '%s\n' "$SECTION" | sed '/./,$!d'   # drop leading blank lines
echo
echo "## Install"
echo
echo "1. Download **$DMG** below and open it."
echo "2. Drag **TESS** onto the **Applications** folder."
if [ -n "${NOTARIZED:-}" ]; then
  echo "3. Open TESS from Applications."
else
  cat <<STEP
3. Open TESS from Applications. TESS isn't notarised by Apple yet, so the first time macOS says it can't verify it:
   click **Done**, open **System Settings › Privacy & Security**, scroll down and click **Open Anyway** next to TESS.
   You only need to do this once.
STEP
fi
cat <<'TAIL'
4. Click the TESS icon in the menu bar › **Settings… › Permissions › Set up everything**, then add a Claude or OpenAI key, or pick an Ollama model, under **Brain**.

Requires macOS 14 Sonoma or later, on Apple silicon or Intel.

**Updating:** quit TESS and drag the new version over the old one. Settings, memory, history and permissions carry over.

**Checking the download:** `shasum -a 256 TESS-*.dmg` should match the line in `SHA256SUMS.txt`.
TAIL
