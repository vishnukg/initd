#!/usr/bin/env bash
# Brightness of the FOCUSED monitor, whichever it is: the keys
# (hyprland.lua, XF86MonBrightnessUp/Down), the quick-settings slider and the
# bar's indicator all go through here.
#
#   brightness.sh up | down          the keys: one step, then the bar is pinged
#   brightness.sh set <percent>      the slider: an absolute level, no ping
#   brightness.sh refresh            the bar: re-read the level, no ping
#
# Laptop panel: brightnessctl on the backlight (down floors at 2% so the
# screen never goes fully dark); the bar reads the level straight from sysfs.
# External monitor: DDC/CI over the DisplayPort AUX channel through ddcutil
# (VCP feature 10), which the backlight path cannot reach -- in clamshell mode
# the keys used to adjust a panel nobody could see. There is no file to read a
# DDC level from, so this script keeps one: the monitor is asked once
# (`getvcp 10`, ~0.4 s) and every write after that is absolute, so the cached
# level and the monitor agree, and the current level is published to
# $XDG_RUNTIME_DIR/initd-brightness/level as "<output> <percent>" for the bar's
# slider and pill. The i2c bus behind a connector comes from
# `ddcutil detect --brief` (~1 s) and is cached per connector too; both caches
# are dropped when a write fails (a replug can move the bus). A write takes
# ~0.35 s and the keys repeat every 33 ms, so a key press that lands while a
# write is in flight is dropped (flock -n): holding the key steps at the
# monitor's pace instead of queueing seconds of writes. The slider's `set`
# waits its turn instead, so the level it ends on is the one that lands.
set -u

STEP="${BRIGHTNESS_STEP:-5}"
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/initd-brightness"

focused_monitor() {
  # Plain-text output, no JSON parser needed: "Monitor DP-1 (ID 1):" opens
  # each block and "focused: yes" marks the one with focus.
  hyprctl monitors 2>/dev/null | awk '/^Monitor /{name=$2} /^[[:space:]]*focused: yes/{print name; exit}'
}

ping_bar() {
  # Every `qs ipc` call needs --any-display (see hyprland.lua).
  qs ipc --any-display call bar refreshBrightness >/dev/null 2>&1 || true
}

clamp() {
  local value="$1"
  (( value < 0 )) && value=0
  (( value > 100 )) && value=100
  echo "${value}"
}

bus_for() {
  # Connector name (DP-1) -> i2c bus number, cached.
  local connector="$1" cache="${STATE_DIR}/${1}" bus
  if [[ -r "${cache}" ]]; then
    cat "${cache}"
    return 0
  fi
  bus="$(ddcutil detect --brief 2>/dev/null \
    | awk -v want="-${connector}" '
        /I2C bus:/ { bus = $3; sub(".*/i2c-", "", bus) }
        /DRM connector:/ && substr($3, length($3) - length(want) + 1) == want { print bus; exit }')"
  [[ -n "${bus}" ]] || return 1
  printf '%s\n' "${bus}" > "${cache}"
  echo "${bus}"
}

read_level() {
  # Ask the monitor: `getvcp 10 --brief` prints "VCP 10 C <current> <max>".
  local bus="$1" cur max
  read -r _ _ _ cur max < <(ddcutil --bus "${bus}" getvcp 10 --brief --sleep-multiplier .3 2>/dev/null)
  [[ "${cur:-}" =~ ^[0-9]+$ && "${max:-}" =~ ^[1-9][0-9]*$ ]] || return 1
  echo $(( cur * 100 / max ))
}

publish() {
  # In place, not via rename: the bar may hold the file open.
  printf '%s %s\n' "$1" "$2" > "${STATE_DIR}/level"
  printf '%s\n' "$2" > "${STATE_DIR}/$1.level"
}

internal() {
  case "$1" in
    up) brightnessctl -q set "${STEP}%+"; ping_bar ;;
    down) brightnessctl --min-val=2 -q set "${STEP}%-"; ping_bar ;;
    set) brightnessctl -q set "$(clamp "$2")%" ;;
    refresh) ;;
  esac
}

external() {
  local connector="$1" action="$2" level_cache="${STATE_DIR}/$1.level" bus current target
  exec 9> "${STATE_DIR}/lock"
  case "${action}" in
    up | down) flock -n 9 || return 0 ;;
    *) flock -w 5 9 || return 1 ;;
  esac
  bus="$(bus_for "${connector}")" || return 1
  if [[ "${action}" != refresh && -r "${level_cache}" ]]; then
    current="$(cat "${level_cache}")"
  else
    current="$(read_level "${bus}")" || { rm -f "${STATE_DIR}/${connector}" "${level_cache}"; return 1; }
  fi
  case "${action}" in
    up) target="$(clamp $(( current + STEP )))" ;;
    down) target="$(clamp $(( current - STEP )))" ;;
    set) target="$(clamp "$3")" ;;
    refresh) publish "${connector}" "${current}"; return 0 ;;
  esac
  # --noverify skips the read-back (one round trip less); the sleep
  # multiplier shortens ddcutil's conservative inter-command waits, which
  # this monitor does not need.
  if ! ddcutil --bus "${bus}" setvcp 10 "${target}" --noverify --sleep-multiplier .3 >/dev/null 2>&1; then
    rm -f "${STATE_DIR}/${connector}" "${level_cache}"
    return 1
  fi
  publish "${connector}" "${target}"
  [[ "${action}" == set ]] || ping_bar
}

main() {
  local action="${1:-}" monitor
  case "${action}" in
    up | down | refresh) ;;
    set) [[ "${2:-}" =~ ^[0-9]+$ ]] || { echo "usage: ${0##*/} set <percent>" >&2; exit 2; } ;;
    *) echo "usage: ${0##*/} up | down | set <percent> | refresh" >&2; exit 2 ;;
  esac
  mkdir -p "${STATE_DIR}"
  monitor="$(focused_monitor)"
  case "${monitor}" in
    # No focused monitor known (no compositor?) or an internal panel: the
    # backlight. Internal connector names per the kernel's DRM naming.
    "" | eDP* | LVDS* | DSI*) internal "${action}" "${2:-}" ;;
    *) external "${monitor}" "${action}" "${2:-}" ;;
  esac
}

main "$@"
