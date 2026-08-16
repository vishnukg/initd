#!/bin/sh
# Waybar power-profile indicator and click handler via Fedora's tuned-ppd API.

service="net.hadess.PowerProfiles"
path="/net/hadess/PowerProfiles"
interface="net.hadess.PowerProfiles"

active_profile() {
  busctl --system get-property "${service}" "${path}" "${interface}" ActiveProfile |
    sed -n 's/^s "\(.*\)"$/\1/p'
}

profile_details() {
  case "$1" in
    power-saver) printf '%s\t%s\t%s\n' "󰌪" "Power Saver" "power-saver" ;;
    balanced)    printf '%s\t%s\t%s\n' "󰾅" "Balanced" "balanced" ;;
    performance) printf '%s\t%s\t%s\n' "󰓅" "Performance" "performance" ;;
    *)           printf '%s\t%s\t%s\n' "󰂑" "Unknown" "unknown" ;;
  esac
}

show() {
  profile="$(active_profile)"
  [ -n "${profile}" ] || {
    printf '%s\n' '{"text":"󰂑","tooltip":"Power profile unavailable","class":"unknown"}'
    exit 1
  }

  IFS='	' read -r icon label class <<EOF
$(profile_details "${profile}")
EOF
  printf '{"text":"%s","tooltip":"Power profile: %s\\nClick to switch profile","class":"%s"}\n' \
    "${icon}" "${label}" "${class}"
}

toggle() {
  current="$(active_profile)"
  case "${current}" in
    power-saver) next="balanced" ;;
    balanced)    next="performance" ;;
    performance) next="power-saver" ;;
    *)
      notify-send -u critical "Power profile" "Could not determine the active profile."
      exit 1
      ;;
  esac

  if ! error="$(busctl --system set-property "${service}" "${path}" "${interface}" \
    ActiveProfile s "${next}" 2>&1)"; then
    printf '%s\n' "${error}" >&2
    notify-send -u critical "Power profile" "Could not switch to ${next}."
    exit 1
  fi

  IFS='	' read -r _ label _ <<EOF
$(profile_details "${next}")
EOF
  notify-send -t 2000 "Power profile" "Switched to ${label}."
}

case "${1:-show}" in
  show) show ;;
  toggle) toggle ;;
  *)
    printf 'Usage: %s [show|toggle]\n' "$0" >&2
    exit 64
    ;;
esac
