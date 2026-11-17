#!/usr/bin/env bash
# Launch bumblebee-status, laid out for i3bar by statusline.py. Its theme,
# base16-powerline, is written by tinty from the color scheme that
# theme-select ($mod+Shift+t) picks.
dir="$HOME/.config/bumblebee-status"
theme=base16-powerline

# Modules, left to right, each with its share of the bar: 10 is a normal
# share, 5 half of one, 20 double. A module never gets less than its text needs.
modules=(cpu:10 memory:10 disk:10 pasink:5 datetime:10)

# The frame and workspace square take the theme's text color. To pick one
# yourself, set it here, e.g. frame="#ffffff".
frame=""

# Before any scheme has been applied, a stock theme
[ -s "$dir/themes/$theme.json" ] || theme=solarized-powerline

# An iconset given with --iconset overrides the theme, so this spacing applies
# to every theme: normal spaces around each icon instead of the thin space the
# stock icons use.
mkdir -p "$dir/themes/icons"
cat > "$dir/themes/icons/roomy.json" <<JSON
{ "defaults": { "padding": "  " } }
JSON

names=() shares=""
for m in "${modules[@]}"; do
    names+=("${m%%:*}")
    shares+="${shares:+,}\"${m%%:*}\":${m##*:}"
done
params=(disk.path=/ "datetime.format=%a %d %b  %H:%M")

bin=/usr/bin/bumblebee-status
if [ ! -x "$bin" ]; then
    echo '{"version":1}'; echo '['
    echo '[{"full_text":"bumblebee-status not installed: paru -S bumblebee-status","color":"#cc241d"}]'
    sleep infinity
fi

# Clicks from i3bar still reach bumblebee-status: only its output is piped
"$bin" -m "${names[@]}" -p "${params[@]}" -t "$theme" --iconset roomy \
    | STATUSLINE_FRAME="$frame" python3 -Iu "$dir/statusline.py" "{$shares}"
