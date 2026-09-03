#!/bin/sh
# Night light: a moderately warm screen (4500 K) via gammastep, run as the
# night-light.service user unit so the keybind, the bar item and the schedule
# timer all drive one process. On Wayland the gamma table resets when the
# client disconnects, so that process stays up while warm is active — the
# unit being active is the state; no state file.
#
#   night-light-toggle.sh            toggle   ($mod+Shift+n, bar bulb)
#   night-light-toggle.sh on|off     explicit
#   night-light-toggle.sh auto       apply the schedule: warm 19:00–07:00
#                                    (night-light-schedule.timer/.service)
#
# `auto` only changes state when the schedule says so; a manual toggle in
# between stands until the next boundary. NIGHT_LIGHT_HOUR overrides the clock
# for testing.

UNIT=night-light.service
ON_HOUR=19
OFF_HOUR=7

# "On" means the unit is active OR a gammastep is running outside it (a stray
# from a crash or an older version of this script). Strays matter: Hyprland
# refuses a second gamma controller for an output and then (0.56.2) leaks the
# refused entry, locking gamma control for the rest of the session — so they
# are always killed, never coexisted with.
is_on() { systemctl --user is-active --quiet "${UNIT}" || pgrep -x gammastep >/dev/null 2>&1; }

kill_strays() {
  systemctl --user is-active --quiet "${UNIT}" && return 0
  pgrep -x gammastep >/dev/null 2>&1 || return 0
  pkill -x gammastep
  # gammastep fades the gamma back (~4s) before exiting; bounded wait.
  i=0
  while pgrep -x gammastep >/dev/null 2>&1 && [ "${i}" -lt 80 ]; do
    sleep 0.1; i=$((i + 1))
  done
}

notify() {
  notify-send -t 1500 -h string:x-canonical-private-synchronous:nightlight \
    "$1  Night light" "$2" 2>/dev/null || true
}

case "${1:-toggle}" in
  on)   want=on ;;
  off)  want=off ;;
  toggle)
    if is_on; then want=off; else want=on; fi
    ;;
  auto)
    hour="${NIGHT_LIGHT_HOUR:-$(date +%H)}"
    hour="${hour#0}"   # "07" -> 7 without bash-only base syntax
    if [ "${hour}" -ge "${ON_HOUR}" ] || [ "${hour}" -lt "${OFF_HOUR}" ]; then
      want=on
    else
      want=off
    fi
    ;;
  *)
    echo "usage: ${0##*/} [toggle|on|off|auto]" >&2
    exit 2
    ;;
esac

if [ "${want}" = on ]; then
  if ! systemctl --user is-active --quiet "${UNIT}"; then
    kill_strays
    # A failed ConditionEnvironment (e.g. under GNOME) is not an error, so check
    # the result rather than the exit status before announcing anything.
    systemctl --user start "${UNIT}" 2>/dev/null
    if is_on; then notify "" "On (4500K)"; fi
  fi
else
  if is_on; then
    # stop waits for gammastep's fade-out, so the bar refresh below sees it gone.
    systemctl --user stop "${UNIT}" 2>/dev/null
    kill_strays
    notify "" "Off"
  fi
fi

# Keep the bar's night-light item in step whichever path ran this.
qs ipc call bar refreshNightLight >/dev/null 2>&1 || true
