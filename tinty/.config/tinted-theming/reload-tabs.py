# Reload every tab in every qutebrowser window, so pages pick up a new color
# scheme (the greasemonkey site scripts and claude.css only apply on load).
# Run inside qutebrowser by apply-scheme: :debug-pyeval --file THIS_FILE
from qutebrowser.utils import objreg

for window in objreg.window_registry.values():
    for tab in window.tabbed_browser.widgets():
        tab.reload()
