#!/bin/sh
# Docker container menu — on-click handler for the Quickshell Docker item.
# rofi: pick a running container, then an action on it.

containers="$(docker ps --format '{{.Names}}\t{{.Status}}' 2>/dev/null)"

if [ -z "${containers}" ]; then
  notify-send -t 2500 "󰡨  Docker" "No running containers" 2>/dev/null || true
  exit 0
fi

container="$(printf '%s\n' "${containers}" | rofi -dmenu -i -p "docker" | cut -f1)"
[ -z "${container}" ] && exit 0

action="$(printf 'logs\nshell\nrestart\nstop' | rofi -dmenu -i -p "${container}")"
case "${action}" in
  logs)    ghostty -e sh -c "docker logs -f --tail 200 '${container}'" & ;;
  shell)   ghostty -e docker exec -it "${container}" sh & ;;
  restart) docker restart "${container}" >/dev/null \
             && notify-send -t 2500 "󰡨  Docker" "Restarted ${container}" 2>/dev/null ;;
  stop)    docker stop "${container}" >/dev/null \
             && notify-send -t 2500 "󰡨  Docker" "Stopped ${container}" 2>/dev/null ;;
esac
