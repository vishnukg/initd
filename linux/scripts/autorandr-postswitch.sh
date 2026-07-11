#!/usr/bin/env bash
# autorandr postswitch hook, linked to ~/.config/autorandr/postswitch by
# linux/setup.sh. Runs after every profile change so the desktop reflows:
# the wallpaper re-spans the new geometry and polybar relaunches on the
# active monitor set. Runs from the udev / lid-listener context — stay
# quiet and never fail the switch.
"${HOME}/.config/display-dpi.sh" "${AUTORANDR_CURRENT_PROFILE:-}" >/dev/null 2>&1 || true
# Wallpaper: duplicate the saved image, centered, on every active head
# (re-reads nitrogen's config so a wallpaper picked in the GUI sticks).
wp="$(awk -F= '/^file=/ {print $2; exit}' "${HOME}/.config/nitrogen/bg-saved.cfg" 2>/dev/null)"
if [[ -n "${wp}" && -f "${wp}" ]]; then
  heads="$(xrandr --listmonitors 2>/dev/null | awk 'NR == 1 {print $2}')"
  for ((i = 0; i < ${heads:-0}; i++)); do
    nitrogen --head="${i}" --set-centered --save "${wp}" >/dev/null 2>&1 || true
  done
else
  nitrogen --restore >/dev/null 2>&1 || true
fi
"${HOME}/.config/polybar/launch.sh" >/dev/null 2>&1 || true
