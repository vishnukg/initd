#!/usr/bin/env bash
# Print the battery percentage (e.g. "75%") for the tmux status bar, or nothing
# if there is no battery. macOS uses pmset; Linux reads /sys/class/power_supply.
if command -v pmset >/dev/null 2>&1; then
    pmset -g batt | grep -o '[0-9]*%' | head -1
else
    for cap in /sys/class/power_supply/BAT*/capacity; do
        [ -r "$cap" ] || continue
        printf '%s%%\n' "$(cat "$cap")"
        break
    done
fi
