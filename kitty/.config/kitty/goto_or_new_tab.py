# Go to tab N, or open a new tab if there is no tab N yet, like i3's
# "workspace number N". kitty numbers tabs by position, so the new tab goes at
# the end (with 2 tabs open, Alt+5 opens tab 3).
#
#   map alt+5 kitten goto_or_new_tab.py 5
from kittens.tui.handler import result_handler


def main(args):
    pass


@result_handler(no_ui=True)
def handle_result(args, answer, target_window_id, boss):
    try:
        n = int(args[1])
    except (IndexError, ValueError):
        return
    tm = boss.active_tab_manager
    if tm is None:
        return
    tabs = tuple(tm.tabs_to_be_shown_in_tab_bar)
    if 1 <= n <= len(tabs):
        tm.set_active_tab(tabs[n - 1])
    else:
        boss.new_tab()
