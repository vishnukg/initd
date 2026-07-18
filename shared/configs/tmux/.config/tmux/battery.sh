#!/usr/bin/env bash
# Keep one long-running tmux status job and publish a fresh battery percentage
# every 30 seconds. tmux reuses the latest line from a #() command while it is
# still running, so the one-second status redraw does not spawn pmset/awk (or a
# new shell) every second. The job exits automatically when the tmux server
# closes its output pipe.

print_battery() {
    if command -v pmset >/dev/null 2>&1; then
        pmset -g batt | awk 'match($0, /[0-9]+%/) { print substr($0, RSTART, RLENGTH); exit }'
        return
    fi

    for cap in /sys/class/power_supply/BAT*/capacity; do
        [ -r "$cap" ] || continue
        IFS= read -r percentage < "$cap"
        printf '%s%%\n' "$percentage"
        return
    done

    # Emit an empty line so tmux clears a stale value on machines without a battery.
    printf '\n'
}

while true; do
    print_battery
    sleep 30
done
