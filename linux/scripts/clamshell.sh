#!/bin/sh
# Clamshell mode: disable the laptop panel while the lid is closed, restore it
# when open. Invoked from hyprland.conf three ways: the lid-switch binds, at
# startup, and on every config reload (exec = reruns on reload) — a reload
# re-applies the static eDP-1 rule and would otherwise re-light a closed lid.

PANEL=eDP-1
# Keep in sync with the eDP-1 monitor rule in hyprland.conf.
PANEL_RULE="eDP-1, preferred, auto, 1.5"

# On config reload, Hyprland spawns exec = commands while still re-applying
# the monitor rules; let those land first so this script has the last word.
sleep 1

if grep -q closed /proc/acpi/button/lid/*/state 2>/dev/null; then
  hyprctl keyword monitor "${PANEL}, disable" >/dev/null
else
  hyprctl keyword monitor "${PANEL_RULE}" >/dev/null
fi
