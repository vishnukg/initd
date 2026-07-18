#!/bin/sh
# Cycle the power-profiles-daemon profile and notify. Bound to $mod+p and the
# waybar power-profile module's left click. Runs in the user session, so PPD's
# allow_active polkit rule permits it without the 49-power-profiles override.

current="$(powerprofilesctl get 2>/dev/null)"
case "${current}" in
  power-saver) next=balanced ;;
  balanced)    next=performance ;;
  performance) next=power-saver ;;
  *)           next=balanced ;;
esac

powerprofilesctl set "${next}" 2>/dev/null

case "${next}" in
  power-saver) icon="" ; label="Power Saver" ;;
  balanced)    icon="" ; label="Balanced" ;;
  performance) icon="" ; label="Performance" ;;
esac

notify-send -t 1500 -h string:x-canonical-private-synchronous:powerprofile \
  "${icon}  Power profile" "${label}" 2>/dev/null || true
