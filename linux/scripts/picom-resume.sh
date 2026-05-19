#!/bin/bash
# Restart picom after resume to prevent GLX compositor artifacts

[ "$1" = "post" ] || exit 0
sleep 1

i3_user=$(ps -eo user,comm | awk '$2=="i3" {print $1; exit}')
[ -z "$i3_user" ] && exit 0

home_dir=$(getent passwd "$i3_user" | cut -d: -f6)
xauth="$home_dir/.Xauthority"
[ -f "$xauth" ] || exit 0

sudo -u "$i3_user" env DISPLAY=:0 XAUTHORITY="$xauth" \
    bash -c 'pkill -x picom 2>/dev/null; sleep 0.3; picom --config ~/.config/picom.conf &'
