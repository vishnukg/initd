#!/usr/bin/env bash
# hypridle's helpers (linux/configs/hypr/hypridle.conf). Kept out of the
# config because hyprlang rewrites `$name` and `{{ }}` inside commands.
#
#   idle.sh dim                 dim to 20% (never brightens an already-dim screen)
#   idle.sh undim               restore the brightness `dim` saved, if it dimmed
#   idle.sh suspend-on-battery  suspend, but only on battery and with nothing playing
#   idle.sh lock                run hyprlock, and run it again if it crashes
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

lock() {
  # hypridle's lock_cmd. One supervisor at a time (the flock), and none at all
  # while some other hyprlock already holds the lock -- the old
  # `pidof hyprlock || hyprlock` guard, which stopped a hyprlock per suspend
  # piling up.
  local guard="${XDG_RUNTIME_DIR:-/tmp}/initd-lock.flock" status restarts=0
  exec 9> "${guard}"
  flock -n 9 || return 0
  pgrep -x hyprlock >/dev/null && return 0
  while :; do
    # fd 9 is closed for hyprlock so the guard dies with this script.
    hyprlock --no-fade-in 9>&-
    status=$?
    # Only a death by signal is restarted: 0 is an unlock, and any other exit
    # (another lock client holding the session, no display) would just fail
    # again. A dead client never unlocks the session -- Hyprland keeps it
    # locked, and misc.allow_session_lock_restore lets the new client take
    # over. SIGTERM counts, so `pkill -x hyprlock` from a TTY is the whole
    # recovery for a lock screen that is up but not drawing.
    ((status > 128)) || return 0
    ((++restarts <= ${LOCK_MAX_RESTARTS:-5})) || return 0
    sleep "${LOCK_RESTART_DELAY:-0.5}"
  done
}

case "${1:-}" in
  dim) dim ;;
  undim) undim ;;
  suspend-on-battery) suspend_on_battery ;;
  lock) lock ;;
  *)
    echo "usage: ${0##*/} dim | undim | suspend-on-battery | lock" >&2
    exit 2
    ;;
esac
