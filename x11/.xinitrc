# Run the system xinitrc.d hooks. 50-systemd-user.sh exports DISPLAY to
# systemd/dbus so user services (e.g. xdg-desktop-portal-gtk, which provides
# the file picker for Vesktop/Electron apps) can open the display.
if [ -d /etc/X11/xinit/xinitrc.d ]; then
  for f in /etc/X11/xinit/xinitrc.d/?*.sh; do
    [ -x "$f" ] && . "$f"
  done
  unset f
fi

exec i3
