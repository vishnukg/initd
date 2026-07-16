#!/bin/sh
# Toggle a moderately warm screen temperature (night light) on/off. Manual
# only — no schedule. Bound to $mod+Shift+n.
#
# On Wayland the gamma table resets when the client disconnects, so gammastep
# must stay running while warm is active (unlike the old X11 one-shot mode).
# The running process itself is the state — no state file needed.

TEMP=4500

if pgrep -x gammastep >/dev/null 2>&1; then
  pkill -x gammastep
  icon="" ; label="Off"
else
  # Constant temperature day and night; -l 0:0 skips location lookup.
  gammastep -P -m wayland -l 0:0 -t "${TEMP}:${TEMP}" >/dev/null 2>&1 &
  icon="" ; label="On (${TEMP}K)"
fi

notify-send -t 1500 -h string:x-canonical-private-synchronous:nightlight \
  "${icon}  Night light" "${label}" 2>/dev/null || true
