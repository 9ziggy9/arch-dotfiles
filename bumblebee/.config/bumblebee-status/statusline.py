#!/usr/bin/env python3
"""Lay out the bumblebee-status line for i3bar.

Sits between bumblebee-status and i3bar:

    bumblebee-status ... | statusline.py SHARES

SHARES is JSON like {"cpu": 10, "pasink": 5}: each module's share of the bar.

- A square with the focused workspace number goes at the far left (in place of
  i3bar's workspace buttons), redrawn as soon as the workspace changes.
- The modules fill the rest of the bar, split by their shares, with their
  text centered in each. Widths are measured with Pango, as i3bar draws them.
- One frame is drawn around all the modules.

Colors come from the bar theme, themes/base16-powerline.json, which tinty
writes from the color scheme: its first segment colors.
Nothing is clickable: the protocol header passed on to i3bar turns click
events off.
"""
import colorsys
import json
import os
import shutil
import subprocess
import sys
import threading

import gi

gi.require_version("Pango", "1.0")
gi.require_version("PangoCairo", "1.0")
import cairo  # noqa: E402
from gi.repository import Pango, PangoCairo  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
FONT = "FiraCode Nerd Font 9"  # must match the bar font in the i3 config
FRAME_PX = 1
# Pixels to leave unused, measured from a screenshot so the workspace square
# touches the left edge of the screen (i3bar draws the frame inside the blocks,
# so the frame's width doesn't need room of its own)
SLACK_PX = int(os.environ.get("STATUSLINE_SLACK", "-1"))

shares = json.loads(sys.argv[1]) if len(sys.argv) > 1 else {}

colors = {"bg": "#282828", "fg": "#ebdbb2", "good": "#98971a", "bad": "#cc241d"}
try:
    with open(os.path.join(HERE, "themes", "base16-powerline.json")) as f:
        theme = json.load(f)
    colors.update(theme["cycle"][0])
    colors.update(theme.get("statusline", {}))
except (OSError, ValueError, KeyError, IndexError):
    pass
frame = os.environ.get("STATUSLINE_FRAME") or colors["fg"]

_layout = PangoCairo.create_layout(cairo.Context(cairo.ImageSurface(cairo.FORMAT_ARGB32, 1, 1)))
_layout.set_font_description(Pango.FontDescription(FONT))


# Outlined arrows: i3bar only draws rectangular borders, so the frame can't
# follow an arrow's slanted edge by itself. Instead each solid powerline
# arrow gets its thin twin (the same shape as a line) in the frame color drawn
# over it, pulled back onto it by negative letter spacing (Pango markup).
# STATUSLINE_ARROW_OUTLINE=no (launch.sh) turns it off.
OUTLINE_ARROWS = os.environ.get("STATUSLINE_ARROW_OUTLINE", "yes") != "no"
THIN_TWIN = {"": "", "": ""}   # solid ◀ ▶ → thin < >


def overlap_spacing(solid, thin):
    """The letter spacing (1024ths of a point) after SOLID that draws THIN
    exactly over it: found by measuring, so it holds for any font."""
    def offset(s):
        _layout.set_markup(f'<span letter_spacing="{s}">{solid}</span>{thin}', -1)
        return _layout.index_to_pos(len(solid.encode())).x - _layout.index_to_pos(0).x
    lo, hi = -100000, 0
    while hi - lo > 1:
        mid = (lo + hi) // 2
        if offset(mid) > 0:
            hi = mid
        else:
            lo = mid
    return hi


_spacing = {}


def outline_arrow(blk):
    """BLK, a solid arrow, with its thin twin over it in the frame color."""
    solid = blk.get("full_text")
    thin = THIN_TWIN.get(solid)
    if not OUTLINE_ARROWS or not blk.get("_decorator") or thin is None:
        return
    if solid not in _spacing:
        _spacing[solid] = overlap_spacing(solid, thin)
    blk["full_text"] = (f'<span letter_spacing="{_spacing[solid]}">{solid}</span>'
                        f'<span foreground="{frame}">{thin}</span>')
    blk["markup"] = "pango"


# ---- battery and disk: text colored from white (good) to red (bad)

DISK_PATH = os.environ.get("STATUSLINE_DISK_PATH", "/")
PLUG = "\uf1e6"
BATTERY_ICONS = ["\uf244", "\uf243", "\uf242", "\uf241", "\uf240"]  # empty .. full
POWER = "/sys/class/power_supply"


def _rgb(c):
    c = c.lstrip("#")
    return tuple(int(c[i:i + 2], 16) / 255 for i in (0, 2, 4))


def _hex(rgb):
    return "#" + "".join(f"{round(max(0, min(1, v)) * 255):02x}" for v in rgb)


def _luminance(c):
    def ch(v):
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (ch(v) for v in _rgb(c))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def _contrast(a, b):
    la, lb = _luminance(a), _luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def gradient(fraction, against):
    """The color FRACTION of the way from colors["good"] (0, the scheme's
    brightest text: white, or near it) to colors["bad"] (1, its red), mixed
    straight across, then made lighter or darker as needed to read on
    AGAINST (4.5:1)."""
    t = max(0.0, min(1.0, fraction))
    color = _hex(a + (b - a) * t for a, b in zip(_rgb(colors["good"]), _rgb(colors["bad"])))
    h, l, s = colorsys.rgb_to_hls(*_rgb(color))
    if not against or _contrast(color, against) >= 4.5:
        return color
    # away from the background: lighter on a dark one, darker on a light one
    target = 1.0 if _luminance(against) < 0.18 else 0.0
    for i in range(1, 41):
        c = _hex(colorsys.hls_to_rgb(h, l + (target - l) * i / 40, s))
        if _contrast(c, against) >= 4.5:
            return c
    return c


def _read(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return ""


def plugged_in():
    try:
        names = os.listdir(POWER)
    except OSError:
        return False
    return any(_read(f"{POWER}/{n}/type") == "Mains" and _read(f"{POWER}/{n}/online") == "1"
               for n in names)


def color_levels(blk):
    """Battery: a plug for an icon while plugged in, else one showing the
    charge; green when full, red when empty. Disk: green when empty, red when
    full. Rebuilt from bumblebee's own values, so it can run more than once."""
    if blk.get("_decorator"):
        return
    name = blk.get("name")
    if name == "battery":
        raw = str(blk.get("_raw", ""))
        digits = "".join(ch for ch in raw.split("%")[0] if ch.isdigit())
        if not digits:
            return
        charge = int(digits)
        icon = PLUG if plugged_in() else BATTERY_ICONS[min(4, max(0, (charge + 12) // 25))]
        blk["full_text"] = f"  {icon}  {raw}  "
        blk["color"] = gradient(1 - charge / 100, blk.get("background"))
    elif name == "disk":
        try:
            usage = shutil.disk_usage(DISK_PATH)
        except OSError:
            return
        blk["color"] = gradient(usage.used / usage.total, blk.get("background"))


def text_px(block):
    """BLOCK's width as i3bar draws it."""
    text = block.get("full_text", "")
    if block.get("markup") == "pango":
        _layout.set_markup(text, -1)
    else:
        # set_text keeps the attributes of earlier markup (an outlined
        # arrow's negative letter spacing), so they're cleared first
        _layout.set_attributes(None)
        _layout.set_text(text, -1)
    return _layout.get_pixel_size()[0]


def screen_px():
    try:
        out = subprocess.run(["i3-msg", "-t", "get_outputs"], capture_output=True, text=True).stdout
        widths = [o["rect"]["width"] for o in json.loads(out) if o.get("active")]
        return widths[0] if widths else 1024
    except Exception:
        return 1024


def focused_workspace():
    try:
        out = subprocess.run(["i3-msg", "-t", "get_workspaces"], capture_output=True, text=True).stdout
        for ws in json.loads(out):
            if ws.get("focused"):
                return ws.get("name", "?")
    except Exception:
        pass
    return "?"


WIDTH = screen_px()
state = {"blocks": None, "workspace": focused_workspace()}
lock = threading.Lock()


def lay_out(blocks):
    """The modules' blocks with widths, alignment and frame, after the workspace square."""
    ws = {
        "full_text": f" {state['workspace']} ",
        "name": "workspace",
        "color": colors["bg"],
        "background": frame,
        "separator": False,
        "separator_block_width": 0,
        "align": "center",
    }
    ws["min_width"] = max(text_px(ws), 22)  # roughly square in the bar

    # group the blocks by module (a powerline arrow belongs to the module after it)
    groups, order = {}, []
    for blk in blocks:
        outline_arrow(blk)
        color_levels(blk)
        key = blk.get("instance") or blk.get("name")
        if key not in groups:
            groups[key] = []
            order.append(key)
        groups[key].append(blk)

    # the first module's own arrow goes: in its place the workspace square
    # ends in an arrow pointing right, into the first module's color
    first = groups[order[0]] if order else []
    while len(first) > 1 and first[0].get("_decorator"):
        first.pop(0)
    ws_arrow = {
        "full_text": "\ue0b0",
        "name": "workspace",
        "color": frame,
        "background": first[-1].get("background") if first else None,
        "separator": False,
        "separator_block_width": 0,
        "border": frame,
        "border_top": FRAME_PX, "border_bottom": FRAME_PX,
        # against the square, which is the frame's color: it doesn't show
        "border_left": FRAME_PX, "border_right": 0,
    }

    avail = WIDTH - SLACK_PX - ws["min_width"] - text_px(ws_arrow) - 2 * FRAME_PX
    need = {k: sum(text_px(b) for b in groups[k]) for k in order}
    share = {k: shares.get(groups[k][-1].get("name"), 10) for k in order}

    # each module gets its share of the space, but never less than its text;
    # whatever those wider modules take is split among the rest
    width, flexible = {}, list(order)
    while flexible:
        room = avail - sum(width.values())
        total = sum(share[k] for k in flexible)
        fixed = [k for k in flexible if need[k] > room * share[k] / total]
        if not fixed:
            for k in flexible:
                width[k] = room * share[k] // total
            # the rounding leftovers go to the last module, so the line is exact
            width[flexible[-1]] += room - sum(width[k] for k in flexible)
            break
        for k in fixed:
            width[k] = need[k]
            flexible.remove(k)

    out = [ws, ws_arrow]
    for i, k in enumerate(order):
        main = groups[k][-1]
        arrows = groups[k][:-1]
        main["min_width"] = max(width[k] - sum(text_px(b) for b in arrows), text_px(main))
        main["align"] = "center"
        for blk in groups[k]:
            blk["separator_block_width"] = 0
            blk["border"] = frame
            blk["border_top"] = blk["border_bottom"] = FRAME_PX
            blk["border_left"] = blk["border_right"] = 0
        out.extend(groups[k])
    out[-1]["border_right"] = FRAME_PX
    return out


def emit():
    """Write the current line; the caller holds the lock."""
    if state["blocks"] is not None:
        sys.stdout.write(json.dumps(lay_out(json.loads(state["blocks"]))) + ",\n")
        sys.stdout.flush()


def watch_workspaces():
    """Redraw as soon as the focused workspace changes."""
    proc = subprocess.Popen(["i3-msg", "-t", "subscribe", "-m", '["workspace"]'],
                            stdout=subprocess.PIPE, text=True)
    for line in proc.stdout:
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if event.get("change") in ("focus", "init", "empty", "rename", "reload"):
            name = focused_workspace()
            with lock:
                if name != state["workspace"]:
                    state["workspace"] = name
                    emit()


threading.Thread(target=watch_workspaces, daemon=True).start()

while True:
    line = sys.stdin.readline()
    if not line:
        break
    body = line.strip().strip(",")
    try:
        blocks = json.loads(body)
    except ValueError:
        blocks = None
    with lock:
        if isinstance(blocks, list) and blocks:
            state["blocks"] = body
            emit()
        elif not isinstance(blocks, list):
            # the protocol header and the opening "[". Clicks are turned off
            # in the header, so i3bar doesn't send them and nothing is clickable
            if isinstance(blocks, dict):
                blocks["click_events"] = False
                line = json.dumps(blocks) + "\n"
            sys.stdout.write(line)
            sys.stdout.flush()
