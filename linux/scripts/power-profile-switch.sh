#!/bin/sh
# Auto-switch power-profiles-daemon between AC and battery.
# Invoked by udev on power_supply changes and once at Hyprland login. Idempotent.
#
# AC      -> performance (plugged in = desk/docked; take the full clocks)
# Battery -> balanced (power-saver caps the CPU hard enough that app launches
#                      visibly lag; drop to it manually via $mod+p when you
#                      need max runtime)

PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

AC_PROFILE=performance
BATTERY_PROFILE=balanced

on_ac() {
  # Primary signal: any Mains-type adapter reporting online.
  for ps in /sys/class/power_supply/*; do
    [ -r "${ps}/type" ] || continue
    if [ "$(cat "${ps}/type")" = "Mains" ] && [ "$(cat "${ps}/online" 2>/dev/null)" = "1" ]; then
      return 0
    fi
  done
  # Fallback for USB-C PD charging (Mains adapter may stay offline): a battery
  # that is charging or topped-off-while-plugged means we are on AC.
  for ps in /sys/class/power_supply/*; do
    [ -r "${ps}/type" ] || continue
    [ "$(cat "${ps}/type")" = "Battery" ] || continue
    case "$(cat "${ps}/status" 2>/dev/null)" in
      Charging|"Not charging") return 0 ;;
    esac
  done
  return 1
}

if on_ac; then
  target="${AC_PROFILE}"
else
  target="${BATTERY_PROFILE}"
fi

# No-op if already on the target profile (avoids needless D-Bus churn on every event).
current="$(powerprofilesctl get 2>/dev/null)"
[ "${current}" = "${target}" ] && exit 0

powerprofilesctl set "${target}" 2>/dev/null || exit 0
