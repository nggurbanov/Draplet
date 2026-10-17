"""Local installer layout; artwork at 2x, Finder coordinates in points."""
from pathlib import Path
root = Path.cwd()  # build-dmg.sh always runs from the repository root
application = str(root / '.build/Draplet.app')
format = 'UDZO'
filesystem = 'HFS+'
files = [application]
symlinks = {'Applications': '/Applications'}
hide_extensions = []  # FinderInfo on the signed app would invalidate its signature
icon = str(root / 'Resources/Draplet.icns')
background = str(root / 'Resources/Installer/background.tiff')
window_rect = ((160, 100), (800, 500))
icon_locations = {'Draplet.app': (310, 270), 'Applications': (535, 270)}
icon_size = 100
text_size = 14
grid_offset = (0, 0)
arrange_by = None
label_pos = 'bottom'
show_icon_preview = False
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
default_view = 'icon-view'
include_icon_view_settings = True
include_list_view_settings = False
