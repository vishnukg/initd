#!/usr/bin/env bash
# The brightness keys (hyprland.lua, XF86MonBrightnessUp/Down): step the
# brightness of the FOCUSED monitor, whichever it is.
#
#   brightness.sh up | down
#
# Laptop panel: brightnessctl on the backlight, as before (down floors at 2%
# so the screen never goes fully dark), then the bar's brightness pill is
# pinged. External monitor: DDC/CI over the DisplayPort AUX channel through
# ddcutil (VCP feature 10), which the backlight path cannot reach -- in
# clamshell mode the keys used to adjust a panel nobody could see. The i2c
# bus behind a connector comes from `ddcutil detect --brief` (~1 s), so it is
# cached per connector under XDG_RUNTIME_DIR and dropped when a write fails
# (a replug can move the bus). A write takes ~0.35 s and the keys repeat every
# 33 ms, so a press that lands while one is in flight is dropped (flock -n):
# holding the key steps at the monitor's pace instead of queueing seconds of
# writes. The bar's slider and pill stay backlight-only; this is the keys.
set -u

STEP="${BRIGHTNESS_STEP:-5}"
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/initd-brightness"

focused_monitor() {
  # Plain-text output, no JSON parser needed: "Monitor DP-1 (ID 1):" opens
  # each block and "focused: yes" marks the one with focus.
  hyprctl monitors 2>/dev/null | awk '/^Monitor /{name=$2} /^[[:space:]]*focused: yes/{print name; exit}'
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

internal() {
  if [[ "$1" == up ]]; then
    brightnessctl -q set "${STEP}%+"
  else
    brightnessctl --min-val=2 -q set "${STEP}%-"
  fi
  # Every `qs ipc` call needs --any-display (see hyprland.lua).
  qs ipc --any-display call bar refreshBrightness >/dev/null 2>&1 || true
}

external() {
  local connector="$1" sign="+" bus
  [[ "$2" == up ]] || sign="-"
  exec 9> "${STATE_DIR}/lock"
  flock -n 9 || return 0
  bus="$(bus_for "${connector}")" || return 1
  # --noverify skips the read-back (one round trip less); the sleep
  # multiplier shortens ddcutil's conservative inter-command waits, which
  # this monitor does not need.
  if ! ddcutil --bus "${bus}" setvcp 10 "${sign}" "${STEP}" --noverify --sleep-multiplier .3 >/dev/null 2>&1; then
    rm -f "${STATE_DIR}/${connector}"
    return 1
  fi
}

main() {
  local direction="${1:-}" monitor
  case "${direction}" in
    up | down) ;;
    *) echo "usage: ${0##*/} up | down" >&2; exit 2 ;;
  esac
  mkdir -p "${STATE_DIR}"
  monitor="$(focused_monitor)"
  case "${monitor}" in
    # No focused monitor known (no compositor?) or an internal panel: the
    # backlight. Internal connector names per the kernel's DRM naming.
    "" | eDP* | LVDS* | DSI*) internal "${direction}" ;;
    *) external "${monitor}" "${direction}" ;;
  esac
}

main "$@"
