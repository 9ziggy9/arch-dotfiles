#!/usr/bin/env bash
# Launch bumblebee-status, laid out for i3bar by statusline.py. Its theme,
# base16-powerline, is written by tinty from the color scheme that
# theme-select ($mod+Shift+t) picks.
dir="$HOME/.config/bumblebee-status"
theme=base16-powerline

# Modules, left to right, each with its share of the bar: 10 is a normal
# share, 5 half of one, 20 double. A module never gets less than its text needs.
modules=(nic:10 cpu:5 memory:5 disk:8 pasink:5 time:5)

# The battery, only on a machine that has one (a laptop), before the volume
if compgen -G "/sys/class/power_supply/BAT*" >/dev/null; then
    with=()
    for m in "${modules[@]}"; do
        [ "${m%%:*}" = pasink ] && with+=(battery:6)
        with+=("$m")
    done
    modules=("${with[@]}")
fi

# The frame and workspace square take the theme's text color. To pick one
# yourself, set it here, e.g. frame="#ffffff".
frame=""

# The frame also runs along the arrows' slanted edges (statusline.py): yes/no
outline_arrows=yes

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
# Network: the connected interfaces only (not the modem or virtual ones),
# with the Wi-Fi network's name ({ssid} needs the iw package) and the address
# The disk whose space is shown (white when empty, red when full)
disk_path=/

params=(
    "disk.path=$disk_path" "disk.format={left} free"
    "memory.format={percent:.0f}%" "cpu.format={:.0f}%"
    nic.states=up "nic.format={ssid} {ip}" "nic.exclude=lo,wwp,virbr,docker,vboxnet,veth,br,tun,.*:avahi"
    time.format=%H:%M
)

bin=/usr/bin/bumblebee-status
if [ ! -x "$bin" ]; then
    echo '{"version":1}'; echo '['
    echo '[{"full_text":"bumblebee-status not installed: paru -S bumblebee-status","color":"#cc241d"}]'
    sleep infinity
fi

# Nothing on the bar is clickable: statusline.py turns clicks off
"$bin" -m "${names[@]}" -p "${params[@]}" -t "$theme" --iconset roomy \
    | STATUSLINE_FRAME="$frame" STATUSLINE_ARROW_OUTLINE="$outline_arrows" STATUSLINE_DISK_PATH="$disk_path" python3 -Iu "$dir/statusline.py" "{$shares}"
