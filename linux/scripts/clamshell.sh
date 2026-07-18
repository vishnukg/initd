#!/bin/sh
# Clamshell mode: disable the laptop panel while the lid is closed and an
# external monitor is active; restore it when open. Invoked from hyprland.conf
# by lid-switch binds and by `exec =` at startup/on config reload.

PANEL=eDP-1
# Keep in sync with the eDP-1 monitor rule in hyprland.conf.
PANEL_RULE="eDP-1, preferred, auto, 1.5"

# Capture focus before reload reapplies the panel rule. Disabling a monitor
# migrates its workspaces to another output and can otherwise focus one of
# those migrated workspaces.
active_workspace() {
  hyprctl activeworkspace 2>/dev/null |
    awk '/^workspace ID / { print $3; exit }'
}

monitor_is_active() {
  hyprctl monitors 2>/dev/null |
    awk -v monitor="$1" '$1 == "Monitor" && $2 == monitor { found = 1 } END { exit !found }'
}

external_is_active() {
  hyprctl monitors 2>/dev/null |
    awk -v panel="${PANEL}" '$1 == "Monitor" && $2 != panel { found = 1 } END { exit !found }'
}

original_workspace="$(active_workspace)"

# On config reload, Hyprland spawns `exec =` while still applying monitor
# rules. Lid events do not need this delay and should respond immediately.
[ "${1:-event}" = "reload" ] && sleep 1

monitor_changed=false

if grep -q closed /proc/acpi/button/lid/*/state 2>/dev/null; then
  # Never remove the only active output. Undocked lid-close suspend remains
  # systemd-logind's responsibility.
  if external_is_active && monitor_is_active "${PANEL}"; then
    hyprctl keyword monitor "${PANEL}, disable" >/dev/null
    monitor_changed=true
  fi
else
  if ! monitor_is_active "${PANEL}"; then
    hyprctl keyword monitor "${PANEL_RULE}" >/dev/null
    monitor_changed=true
  fi
fi

# A monitor removal can focus a workspace that was migrated from that output.
# Restore focus only after an actual monitor change, and only if it moved.
if [ "${monitor_changed}" = true ] && [ -n "${original_workspace}" ]; then
  current_workspace="$(active_workspace)"
  if [ "${current_workspace}" != "${original_workspace}" ]; then
    hyprctl dispatch workspace "${original_workspace}" >/dev/null
  fi
fi
