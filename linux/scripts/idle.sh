#!/usr/bin/env bash
# hypridle's helpers (linux/configs/hypr/hypridle.conf). Kept out of the
# config because hyprlang rewrites `$name` and `{{ }}` inside commands.
#
#   idle.sh dim                 dim to 20% (never brightens an already-dim screen)
#   idle.sh undim               restore the brightness `dim` saved, if it dimmed
#   idle.sh suspend-on-battery  suspend, but only on battery and with nothing playing
set -u

POWER_SUPPLY="${IDLE_POWER_SUPPLY:-/sys/class/power_supply}"
FLAG="${XDG_RUNTIME_DIR:-/tmp}/initd-idle-dimmed"
DIM_PERCENT=20

dim() {
  local current
  current="$(brightnessctl -m 2>/dev/null | cut -d, -f4 | tr -d '%')"
  [[ "${current}" =~ ^[0-9]+$ ]] || return 0
  # Already at or below the dim level: nothing to save, nothing to undo.
  ((current > DIM_PERCENT)) || return 0
  brightnessctl -q -s set "${DIM_PERCENT}%" && : > "${FLAG}"
}

undim() {
  # Only undo our own dim: a restore without it would apply whatever stale
  # value brightnessctl saved last time.
  [[ -e "${FLAG}" ]] || return 0
  rm -f "${FLAG}"
  # -q is ignored for a restore, which prints the device summary.
  brightnessctl -q -r >/dev/null
}

on_battery() {
  local supply has_battery=false
  for supply in "${POWER_SUPPLY}"/*; do
    case "$(cat "${supply}/type" 2>/dev/null)" in
      Battery) has_battery=true ;;
      # Any charger online (the barrel jack, or USB-C power delivery) means
      # plugged in.
      Mains | USB*) [[ "$(cat "${supply}/online" 2>/dev/null)" == 1 ]] && return 1 ;;
    esac
  done
  # A machine with no battery is never "on battery".
  [[ "${has_battery}" == true ]]
}

suspend_on_battery() {
  on_battery || return 0
  # Music or a call keeps going: idle input does not mean idle machine.
  if playerctl -a status 2>/dev/null | grep -qx Playing; then
    return 0
  fi
  systemctl suspend
}

case "${1:-}" in
  dim) dim ;;
  undim) undim ;;
  suspend-on-battery) suspend_on_battery ;;
  *)
    echo "usage: ${0##*/} dim | undim | suspend-on-battery" >&2
    exit 2
    ;;
esac
