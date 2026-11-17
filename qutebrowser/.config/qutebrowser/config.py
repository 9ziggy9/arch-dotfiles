# qutebrowser config
# pylint: disable=undefined-variable  (c and config are provided by qutebrowser)

# Settings changed in the browser (:set) are not saved; everything lives here.
config.load_autoconfig(False)


# ------------------------------------------------------------------ colors
# Taken from the kitty theme, which theme-select ($mod+Shift+t) writes from the
# emacs theme, so the browser matches emacs, kitty, rofi and the status bar.
# theme-select reloads this file in a running qutebrowser (:config-source).

import os
import re

def kitty_colors(path=os.path.expanduser("~/.config/kitty/current-theme.conf")):
    colors = {}
    try:
        with open(path) as f:
            for line in f:
                m = re.match(r"\s*(\w+)\s+(#[0-9a-fA-F]{6})\s*$", line)
                if m:
                    colors[m.group(1)] = m.group(2)
    except OSError:
        pass
    return colors

k = kitty_colors()
bg       = k.get("background", "#282828")
fg       = k.get("foreground", "#ebdbb2")
alt_bg   = k.get("inactive_tab_background", k.get("color0", bg))
dim      = k.get("inactive_tab_foreground", k.get("color8", fg))
sel_bg   = k.get("active_tab_background", k.get("selection_background", "#c9a66b"))
sel_fg   = k.get("active_tab_foreground", k.get("selection_foreground", "#1c1c1c"))
accent   = k.get("cursor", k.get("color4", fg))
red      = k.get("color1", "#cc241d")
green    = k.get("color2", "#98971a")
yellow   = k.get("color3", "#d79921")
blue     = k.get("color4", "#458588")
border   = k.get("inactive_border_color", alt_bg)

# Tabs: every tab on the muted shade; the selected one is told apart by its
# amber bold title (fonts.tabs.selected, below) rather than an amber tab
c.colors.tabs.bar.bg = bg
for kind in ("even", "odd"):
    setattr(getattr(c.colors.tabs, kind), "bg", alt_bg)
    setattr(getattr(c.colors.tabs, kind), "fg", dim)
    setattr(getattr(c.colors.tabs.selected, kind), "bg", alt_bg)
    setattr(getattr(c.colors.tabs.selected, kind), "fg", sel_bg)
    setattr(getattr(c.colors.tabs.pinned, kind), "bg", alt_bg)
    setattr(getattr(c.colors.tabs.pinned, kind), "fg", dim)
    setattr(getattr(c.colors.tabs.pinned.selected, kind), "bg", alt_bg)
    setattr(getattr(c.colors.tabs.pinned.selected, kind), "fg", sel_bg)
c.colors.tabs.indicator.start = blue
c.colors.tabs.indicator.stop = green
c.colors.tabs.indicator.error = red

# Status bar and the command / URL line
c.colors.statusbar.normal.bg = bg
c.colors.statusbar.normal.fg = fg
c.colors.statusbar.command.bg = bg
c.colors.statusbar.command.fg = fg
c.colors.statusbar.insert.bg = alt_bg
c.colors.statusbar.insert.fg = green
c.colors.statusbar.passthrough.bg = alt_bg
c.colors.statusbar.passthrough.fg = blue
c.colors.statusbar.caret.bg = alt_bg
c.colors.statusbar.caret.fg = accent
c.colors.statusbar.caret.selection.bg = sel_bg
c.colors.statusbar.caret.selection.fg = sel_fg
c.colors.statusbar.progress.bg = accent
c.colors.statusbar.url.fg = fg
c.colors.statusbar.url.success.http.fg = fg
c.colors.statusbar.url.success.https.fg = green
c.colors.statusbar.url.error.fg = red
c.colors.statusbar.url.warn.fg = yellow
c.colors.statusbar.url.hover.fg = accent
c.colors.statusbar.private.bg = alt_bg
c.colors.statusbar.private.fg = fg
c.colors.statusbar.command.private.bg = alt_bg
c.colors.statusbar.command.private.fg = fg

# Completion (the list under the URL / command line)
c.colors.completion.fg = fg
c.colors.completion.odd.bg = bg
c.colors.completion.even.bg = alt_bg
c.colors.completion.category.bg = bg
c.colors.completion.category.fg = accent
c.colors.completion.category.border.top = bg
c.colors.completion.category.border.bottom = bg
c.colors.completion.item.selected.bg = sel_bg
c.colors.completion.item.selected.fg = sel_fg
c.colors.completion.item.selected.border.top = sel_bg
c.colors.completion.item.selected.border.bottom = sel_bg
c.colors.completion.item.selected.match.fg = red
c.colors.completion.match.fg = accent
c.colors.completion.scrollbar.bg = bg
c.colors.completion.scrollbar.fg = dim

# Link hints (f): the selection amber, like rofi's selected row
c.colors.hints.bg = sel_bg
c.colors.hints.fg = sel_fg
c.colors.hints.match.fg = red
c.hints.border = f"1px solid {sel_fg}"

# Messages, prompts, key hints, downloads
c.colors.messages.info.bg = bg
c.colors.messages.info.fg = fg
c.colors.messages.info.border = border
c.colors.messages.warning.bg = bg
c.colors.messages.warning.fg = yellow
c.colors.messages.warning.border = yellow
c.colors.messages.error.bg = bg
c.colors.messages.error.fg = red
c.colors.messages.error.border = red
c.colors.prompts.bg = alt_bg
c.colors.prompts.fg = fg
c.colors.prompts.border = f"1px solid {border}"
c.colors.prompts.selected.bg = sel_bg
c.colors.prompts.selected.fg = sel_fg
c.colors.keyhint.bg = alt_bg
c.colors.keyhint.fg = fg
c.colors.keyhint.suffix.fg = accent
c.colors.downloads.bar.bg = bg
c.colors.downloads.start.bg = blue
c.colors.downloads.stop.bg = green
c.colors.downloads.error.bg = red
c.colors.downloads.start.fg = bg
c.colors.downloads.stop.fg = bg
c.colors.downloads.error.fg = bg

# Pages: the theme's background before a page paints (no white flash)
c.colors.webpage.bg = bg

# Dark mode for every website, whatever the theme: sites with their own dark
# version are asked for it, and Chromium darkens the rest (photos are left
# alone). Changes to darkmode settings need a qutebrowser restart (:restart).
c.colors.webpage.preferred_color_scheme = "dark"
c.colors.webpage.darkmode.enabled = True
c.colors.webpage.darkmode.policy.images = "smart"


# ------------------------------------------------------------------ search
# Google for searches: what you type in the URL bar that isn't an address
c.url.searchengines = {"DEFAULT": "https://www.google.com/search?q={}"}

# Google when qutebrowser starts and for new tabs opened without a URL
c.url.start_pages = ["https://www.google.com"]
c.url.default_page = "https://www.google.com"

# Google sign-in rejects qutebrowser's engine (an older Chromium) with "This
# browser or app may not be secure", so on the sign-in page only, qutebrowser
# says it is Firefox. qutebrowser does this itself at startup (its "ua-google"
# quirk), but a config reload with --clear drops that; set here, it stays.
config.set("content.headers.user_agent",
           "Mozilla/5.0 ({os_info}; rv:149.0) Gecko/20100101 Firefox/149.0",
           "https://accounts.google.com/*")


# ------------------------------------------------------------------ fonts
# kitty's font for the whole interface (tabs, URL bar, command line, lists).
# 9pt rather than kitty's 10pt keeps the tab bar and the bottom bar thin (16px).
# Web pages still use their own fonts.
c.fonts.default_family = "MesloLGS Nerd Font Mono"
c.fonts.default_size = "9pt"
c.statusbar.padding = {"top": 0, "bottom": 0, "left": 0, "right": 0}  # with the tabs, 16px tall


# ------------------------------------------------------------------ tabs
# Tabs split the bar evenly, in the interface font (above). qutebrowser has no tab border
# setting, so the tab indicator (a strip at each tab's left edge, normally a
# loading bar) is made a 1px full-height line in the frame color: a divider
# between tabs. While a page loads it still shows the progress colors, then
# goes back to the frame color.
c.fonts.tabs.selected = "bold default_size default_family"
c.fonts.tabs.unselected = "default_size default_family"
c.tabs.favicons.show = "never"
c.tabs.title.alignment = "left"
c.tabs.title.format = "{index} {current_title}"
c.tabs.title.format_pinned = "{index}"
c.tabs.padding = {"top": 0, "bottom": 1, "left": 0, "right": 8}  # 16px, like the bottom bar
c.tabs.max_width = -1                # split the whole bar between the tabs
c.tabs.min_width = -1
c.tabs.indicator.width = 1
c.tabs.indicator.padding = {"top": 0, "bottom": 0, "left": 0, "right": 8}
c.colors.tabs.indicator.stop = fg    # the divider, once a page has loaded


# ------------------------------------------------------------------ Alt bindings
# The same keys as kitty's tab bindings (kitty.conf), all on Alt.
# They replace qutebrowser's own Alt+1..9 (plain tab-focus; Alt+9 was "last").

from qutebrowser.api import cmdutils

def _tab_focus_or_open(win_id: int, index: int) -> None:
    """Go to tab N, or ask for a URL to open in a new tab if there is no tab N
    (like i3's workspace keys, and Alt+N in kitty). Uses qutebrowser
    internals; if those change, it falls back to plain :tab-focus."""
    from qutebrowser.commands import runners
    runner = runners.CommandRunner(win_id)
    try:
        from qutebrowser.utils import objreg
        tabs = objreg.get("tabbed-browser", scope="window", window=win_id).widget.count()
    except Exception:
        runner.run_safely(f"tab-focus --no-last {index}")
        return
    if 1 <= index <= tabs:
        runner.run_safely(f"tab-focus --no-last {index}")
    else:
        runner.run_safely("cmd-set-text -s :open -t")

# registered once: reloading the config (:config-source) must not add it again
try:
    from qutebrowser.misc import objects as _objects
    _registered = "tab-focus-or-open" in _objects.commands
except Exception:
    _registered = False
if not _registered:
    cmdutils.register(name="tab-focus-or-open")(
        cmdutils.argument("win_id", value=cmdutils.Value.win_id)(_tab_focus_or_open))

config.bind("<Alt-Return>", "cmd-set-text -s :open -t")    # new tab: type a URL
config.bind("<Alt-w>", "tab-close")
config.bind("<Alt-h>", "tab-prev")
config.bind("<Alt-l>", "tab-next")
config.bind("<Alt-Shift-h>", "tab-move -")
config.bind("<Alt-Shift-l>", "tab-move +")
config.bind("<Alt-Escape>", "mode-enter caret")            # vim-style text selection
config.bind("<Alt-x>", "cmd-set-text :")
# In the command palette (and the : line), Ctrl+j/k move down/up the list,
# like rofi. Ctrl+k replaces readline's kill-to-end-of-line there.
config.bind("<Ctrl-j>", "completion-item-focus next", mode="command")
config.bind("<Ctrl-k>", "completion-item-focus prev", mode="command")                    # like M-x: every command, searchable

# Link hints: Alt+Space (or f) numbers every link and button on the page; type
# a number to click it, or type part of a link's text to narrow them down
c.hints.mode = "number"
config.bind("<Alt-Space>", "hint")
for n in range(1, 10):
    config.bind(f"<Alt-{n}>", f"tab-focus-or-open {n}")
