#!/usr/bin/env bash
# hypridle's helpers (linux/configs/hypr/hypridle.conf). Kept out of the
# config because hyprlang rewrites `$name` and `{{ }}` inside commands.
#
#   idle.sh dim                 dim to 20% (never brightens an already-dim screen)
#   idle.sh undim               restore the brightness `dim` saved, if it dimmed
#   idle.sh can-suspend         exit 0 on battery with nothing playing, else 1
#                               (hypridle's condition_cmd for the suspend step)
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
  # The battery's own status decides, not the chargers' online flags. On a
  # charger it reads Charging, Full or Not charging; only Discharging means
  # running on it. The USB-C (UCSI) power supply's online flag can go stale:
  # on 2026-11-08 the controller timed out one command
  # (GET_CONNECTOR_STATUS failed (-110)), the driver stopped seeing plug
  # events, and the Dell's supply read online=1 for minutes after it was
  # unplugged while the battery correctly read Discharging. A machine with no
  # battery never matches, so it is never "on battery".
  local supply
  for supply in "${POWER_SUPPLY}"/*; do
    [[ "$(cat "${supply}/type" 2>/dev/null)" == Battery ]] || continue
    [[ "$(cat "${supply}/status" 2>/dev/null)" == Discharging ]] && return 0
  done
  return 1
}

can_suspend() {
  # hypridle runs this as the suspend listener's condition_cmd and suspends
  # only on exit 0; with condition_retry it asks again every 30 s while the
  # machine stays idle, so a charger unplugged after the timeout still leads
  # to a suspend. The old form (this check inside on-timeout, which ran once)
  # never did. Kept fast: hypridle runs it synchronously on its event loop.
  on_battery || return 1
  # Music or a call keeps going: idle input does not mean idle machine.
  if playerctl -a status 2>/dev/null | grep -qx Playing; then
    return 1
  fi
  return 0
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
  can-suspend) can_suspend ;;
  lock) lock ;;
  *)
    echo "usage: ${0##*/} dim | undim | can-suspend | lock" >&2
    exit 2
    ;;
esac
