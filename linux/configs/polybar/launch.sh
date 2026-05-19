#!/bin/bash
# Kill any running polybar instances
killall -q polybar

# Wait until all instances have shut down
while pgrep -u "$UID" -x polybar > /dev/null; do sleep 0.1; done

# Launch bar on each connected monitor
if type xrandr > /dev/null 2>&1; then
    for m in $(xrandr --query | grep " connected" | cut -d" " -f1); do
        MONITOR="$m" GTK_ICON_THEME=Papirus polybar main 2>&1 | tee -a /tmp/polybar-"$m".log &
    done
else
    polybar --reload main &
fi
