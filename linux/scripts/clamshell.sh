#!/bin/sh
# Clamshell mode: disable the laptop panel while the lid is closed and an
# external monitor is active; restore it when open. It also locks and turns
# the panel off immediately on a real lid-close event before logind suspends.
# Invoked from hyprland.lua by lid-switch binds and by the config.reloaded hook.

PANEL=eDP-1
# Keep in sync with the eDP-1 monitor rule in hyprland.lua.
PANEL_RULE="eDP-1, preferred, auto, 1.25"

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
is_reload=false
[ "${1:-event}" = "reload" ] && { is_reload=true; sleep 1; }

monitor_changed=false
lid_closed=false
grep -q closed /proc/acpi/button/lid/*/state 2>/dev/null && lid_closed=true

if [ "${lid_closed}" = true ]; then
  # Lock + panel off only for a real lid-close event, not a config reload
  # that happens to run while already closed (e.g. testing a config change
  # while docked) — that shouldn't re-lock the session every time.
  if [ "${is_reload}" = false ]; then
    loginctl lock-session >/dev/null 2>&1
    hyprctl dispatch "hl.dsp.dpms(\"off\")" >/dev/null
  fi

  # Never remove the only active output.
  if external_is_active && monitor_is_active "${PANEL}"; then
    hyprctl keyword monitor "${PANEL}, disable" >/dev/null
    monitor_changed=true
  fi
else
  [ "${is_reload}" = false ] && hyprctl dispatch "hl.dsp.dpms(\"on\")" >/dev/null

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
    hyprctl dispatch "hl.dsp.focus({workspace = ${original_workspace}})" >/dev/null
  fi
fi
