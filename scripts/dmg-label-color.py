# Sets the hidden background colour of the installer window to TESS navy.
#   python3 scripts/dmg-label-color.py /Volumes/TESS/.DS_Store
#
# Finder chooses the colour of the names under the icons (black or white) from this colour,
# not from the background picture. dmgbuild leaves it white when a picture is used, so the
# names came out dark on the navy artwork, in Light and Dark Mode alike.
import sys

from ds_store import DSStore

NAVY = (12 / 255, 24 / 255, 43 / 255)  # top of the background gradient

with DSStore.open(sys.argv[1], "r+") as store:
    view = store["."]["icvp"]
    view["backgroundColorRed"], view["backgroundColorGreen"], view["backgroundColorBlue"] = NAVY
    store["."]["icvp"] = view
print("Label colour set for", sys.argv[1])
