#!/bin/sh
# Toggle a moderately warm screen temperature (night light) on/off. Manual
# only — no schedule. Bound to $mod+Shift+n and to the bar's night-light item.
#
# On Wayland the gamma table resets when the client disconnects, so gammastep
# must stay running while warm is active (unlike the old X11 one-shot mode).
# The running process itself is the state — no state file needed.

TEMP=4500

if pgrep -x gammastep >/dev/null 2>&1; then
  pkill -x gammastep
  icon="" ; label="Off" ; wait_exit=1
else
  # Constant temperature day and night; -l 0:0 skips location lookup.
  gammastep -P -m wayland -l 0:0 -t "${TEMP}:${TEMP}" >/dev/null 2>&1 &
  icon="" ; label="On (${TEMP}K)" ; wait_exit=0
fi

notify-send -t 1500 -h string:x-canonical-private-synchronous:nightlight \
  "${icon}  Night light" "${label}" 2>/dev/null || true

# gammastep fades the gamma back over ~4s before it exits. The bar reads state
# from the process, so wait for it to be gone before the refresh below or the
# item stays amber until its next 30s poll. Bounded, so a wedged process cannot
# hang this script.
if [ "${wait_exit}" = 1 ]; then
  i=0
  while pgrep -x gammastep >/dev/null 2>&1 && [ "${i}" -lt 80 ]; do
    sleep 0.1; i=$((i + 1))
  done
fi

# Keep the bar's night-light item in step whether this ran from the keybind or
# from a click on that item.
qs ipc call bar refreshNightLight >/dev/null 2>&1 || true
