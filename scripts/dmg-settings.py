# Layout of the TESS installer window, read by dmgbuild (https://dmgbuild.readthedocs.io).
# Used by scripts/make-dmg.sh — values arrive through dmgbuild's -D options.
import os.path

app = defines["app"]
app_name = os.path.basename(app)

# make-dmg.sh builds read-write first (to adjust the label colour), then compresses to ULFO.
format = defines.get("format", "ULFO")
filesystem = "HFS+"
files = [app]
applications = "Applications"
symlinks = {applications: "/Applications"}
hide_extension = [app_name]

icon = defines.get("volume_icon")
background = defines["background"]

# The background is 640×420 (the window adds a title bar); icon positions are the centres of the icons.
window_rect = ((200, 140), (640, 453))  # 420 + the 33-point title bar
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
    applications: (470, 205),
}
