#!/usr/bin/env bash
# Launch bumblebee-status, laid out for i3bar by statusline.py. Its theme,
# kitty-powerline, is made by bar-theme.py from the kitty (= emacs) colors
# that theme-select ($mod+Shift+t) picks.
dir="$HOME/.config/bumblebee-status"
theme=kitty-powerline

# Modules, left to right, each with its share of the bar: 10 is a normal
# share, 5 half of one, 20 double. A module never gets less than its text needs.
modules=(cpu:10 memory:10 disk:10 pasink:5 datetime:10)

# The frame and workspace square take the theme's text color. To pick one
# yourself, set it here, e.g. frame="#ffffff".
frame=""

# Remake the bar theme if kitty's colors are newer (or it doesn't exist yet)
kitty_colors="$HOME/.config/kitty/current-theme.conf"
if [ ! -s "$dir/themes/$theme.json" ] || [ "$kitty_colors" -nt "$dir/themes/$theme.json" ]; then
    python3 -I "$dir/bar-theme.py"
fi

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
