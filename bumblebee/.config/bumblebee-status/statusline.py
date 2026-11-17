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

Colors come from colors.json, written by bar-theme.py from the kitty theme.
Clicks from i3bar don't come through here; they go straight to
bumblebee-status.
"""
import json
import os
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

colors = {"bg": "#282828", "fg": "#ebdbb2", "frame": "#ffffff"}
try:
    with open(os.path.join(HERE, "colors.json")) as f:
        colors.update(json.load(f))
except (OSError, ValueError):
    pass
frame = os.environ.get("STATUSLINE_FRAME") or colors["frame"]

_layout = PangoCairo.create_layout(cairo.Context(cairo.ImageSurface(cairo.FORMAT_ARGB32, 1, 1)))
_layout.set_font_description(Pango.FontDescription(FONT))


def text_px(block):
    text = block.get("full_text", "")
    if block.get("markup") == "pango":
        _layout.set_markup(text, -1)
    else:
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
        key = blk.get("instance") or blk.get("name")
        if key not in groups:
            groups[key] = []
            order.append(key)
        groups[key].append(blk)

    avail = WIDTH - SLACK_PX - ws["min_width"] - 2 * FRAME_PX
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

    out = [ws]
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
    out[1]["border_left"] = FRAME_PX
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
            # the protocol header and the opening "["
            sys.stdout.write(line)
            sys.stdout.flush()
