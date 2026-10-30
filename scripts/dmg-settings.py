# Layout of the TESS installer window, read by dmgbuild (https://dmgbuild.readthedocs.io).
# Used by scripts/make-dmg.sh — values arrive through dmgbuild's -D options.
import os.path

app = defines["app"]
app_name = os.path.basename(app)

format = "ULFO"            # LZFSE-compressed, read-only (macOS 10.11+)
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
hide_extension = [app_name]

icon = defines.get("volume_icon")
background = defines["background"]

# The background is 640×420 (the window adds a title bar); icon positions are the centres of the icons.
window_rect = ((200, 140), (640, 440))  # +20 for the title bar
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 112
text_size = 13
icon_locations = {
    app_name: (170, 205),
    "Applications": (470, 205),
}
