#!/bin/bash
# Kill any running polybar instances
killall -q polybar

# Wait until all instances have shut down
while pgrep -u "$UID" -x polybar > /dev/null; do sleep 0.1; done

# Per-monitor bar scaling. The bar's reference design is Xft.dpi 144: fonts
# scale via polybar's dpi key (hence the /1.5 point sizes vs the old dpi=96
# values); pixel values (height, baseline offsets, tray) scale by dpi/144.
# The HiDPI laptop panel always gets the 144 design; external monitors follow
# the session Xft.dpi, set per autorandr profile by display-dpi.sh.
session_dpi="$(xrdb -query 2>/dev/null | awk '/^Xft\.dpi:/ {print $2}')"
session_dpi="${session_dpi:-144}"

# The backlight module only works on the laptop panel — external monitor
# brightness isn't exposed via /sys/class/backlight (that would need DDC).
modules_laptop="cpu memory wlan pulseaudio backlight powerprofile battery tray date"
modules_external="cpu memory wlan pulseaudio powerprofile battery tray date"

bar_env() {
    local dpi="$1"
    px() { echo $(( ($1 * dpi + 72) / 144 )); }
    local font="FiraCode Nerd Font Mono:style=Bold"
    export POLYBAR_DPI="$dpi"
    export POLYBAR_HEIGHT="$(px 46)"
    export POLYBAR_FONT0="${font}:size=13.3;$(px 5)"
    export POLYBAR_FONT1="${font}:size=20.7;$(px 7)"
    export POLYBAR_FONT2="${font}:size=14;$(px 6)"
    export POLYBAR_TRAYPAD="$(px 6)px"
    export POLYBAR_TRAYMAX="$(px 16)"
}

# Launch bar on each active monitor. --listmonitors excludes outputs that are
# connected but switched off (e.g. the laptop panel while docked with the lid
# closed under autorandr).
if type xrandr > /dev/null 2>&1; then
    for m in $(xrandr --listmonitors | awk 'NR > 1 {print $NF}'); do
        case "$m" in
            eDP*) bar_env 144              # HiDPI laptop panel
                  export POLYBAR_MODULES_RIGHT="$modules_laptop" ;;
            *)    bar_env "$session_dpi"   # external monitors
                  export POLYBAR_MODULES_RIGHT="$modules_external" ;;
        esac
        MONITOR="$m" GTK_ICON_THEME=Papirus polybar main 2>&1 | tee -a /tmp/polybar-"$m".log &
    done
else
    bar_env "$session_dpi"
    export POLYBAR_MODULES_RIGHT="$modules_laptop"
    polybar --reload main &
fi
