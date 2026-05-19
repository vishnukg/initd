#!/bin/bash
# Close xss-lock's sleep inhibitor fd — signals systemd it's safe to suspend
[ -n "${XSS_SLEEP_LOCK_FD}" ] && eval "exec ${XSS_SLEEP_LOCK_FD}>&-"

LOCK_IMG="$HOME/.cache/lockscreen.png"
if [ -f "$LOCK_IMG" ]; then
    i3lock -i "$LOCK_IMG" -e -n
else
    i3lock -c 1a1b2e -e -n
fi
