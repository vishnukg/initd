#!/bin/sh
# Toggle a moderately warm screen temperature (night light) on/off. Manual
# only — no daemon, no schedule. Bound to $mod+n. Uses gammastep one-shot
# mode, so nothing keeps running; a state file remembers that warm is active.
# Gamma resets on X restart, so i3 startup clears the state file to match.

TEMP=4500
STATE="${XDG_CACHE_HOME:-${HOME}/.cache}/night-light-on"

if [ -e "${STATE}" ]; then
  gammastep -x >/dev/null 2>&1
  rm -f "${STATE}"
  icon="" ; label="Off"
else
  gammastep -P -O "${TEMP}" >/dev/null 2>&1
  touch "${STATE}"
  icon="" ; label="On (${TEMP}K)"
fi

notify-send -t 1500 -h string:x-canonical-private-synchronous:nightlight \
  "${icon}  Night light" "${label}" 2>/dev/null || true
