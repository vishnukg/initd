#!/bin/sh
# Trigger immediate WiFi reconnect after resume instead of waiting for NM's scan timer.
[ "$1" = "post" ] || exit 0
IFACE=$(ip -o link show | awk '$2 ~ /^wlp/ {gsub(/:/, "", $2); print $2; exit}')
[ -n "$IFACE" ] && /usr/bin/nmcli device connect "$IFACE" >/dev/null 2>&1 || true
