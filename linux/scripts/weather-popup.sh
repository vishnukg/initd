#!/bin/sh
# Weather details popup — on-click handler for the Quickshell weather item.
# One dunst notification with location, conditions, wind, humidity and rain.

# URL-safe format: + for spaces, | as line separator (raw spaces make curl
# reject the URL with exit 3).
report="$(curl -sf --max-time 10 'https://wttr.in/?format=%l|%c+%C,+%t+(feels+%f)|%w+wind,+%h+humidity|%p+precipitation,+%m' | tr '|' '\n')"

if [ -z "${report}" ]; then
  notify-send -t 3000 "Weather" "wttr.in unreachable" 2>/dev/null || true
  exit 0
fi

location="$(printf '%s\n' "${report}" | head -1)"
details="$(printf '%s\n' "${report}" | tail -n +2)"
notify-send -t 8000 -h string:x-canonical-private-synchronous:weather \
  "  ${location}" "${details}" 2>/dev/null || true

# Keep the bar temperature in sync with the fresh popup result.
qs ipc call bar refreshWeather >/dev/null 2>&1 || true
