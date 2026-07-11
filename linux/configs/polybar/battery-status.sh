#!/usr/bin/env bash
# Battery indicator (custom/script). polybar's internal battery module maps
# the firmware's "Not charging" hold state (battery kept at its charge
# threshold while AC / USB-C PD powers the machine) to "discharging" — this
# script shows plugged-in for it instead. Detects devices by type, so no
# per-machine battery/adapter name patching is needed.

bat="" ac=""
for d in /sys/class/power_supply/*; do
  case "$(cat "${d}/type" 2>/dev/null)" in
    Battery) [[ -z "${bat}" ]] && bat="${d}" ;;
    Mains)   [[ -z "${ac}"  ]] && ac="${d}" ;;
  esac
done
[[ -z "${bat}" ]] && exit 0

cap="$(cat "${bat}/capacity" 2>/dev/null)"
cap="${cap:-0}"
status="$(cat "${bat}/status" 2>/dev/null)"
online="$(cat "${ac}/online" 2>/dev/null)"

# Colors mirror [colors] in config.ini.
blue="#89b4fa" red="#f7768e" green="#9ece6a"

if [[ "${online}" == "1" ]]; then
  if [[ "${status}" == "Charging" ]]; then
    icon="󰂄" color="${green}"   # actively charging
  else
    icon="󰚥" color="${blue}"    # plugged in; battery full or held at threshold
  fi
else
  color="${blue}"
  (( cap <= 10 )) && color="${red}"
  if   (( cap >= 90 )); then icon="󰁹"
  elif (( cap >= 60 )); then icon="󰂀"
  elif (( cap >= 35 )); then icon="󰁾"
  elif (( cap >= 15 )); then icon="󰁺"
  else icon="󰂎"
  fi
fi

printf '%%{F%s}%%{T2}%s%%{T-}%%{F-} %s%%\n' "${color}" "${icon}" "${cap}"
