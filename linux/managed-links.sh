#!/usr/bin/env bash

# Linux-only managed symlinks. Appended to the shared MANAGED_LINKS array.

: "${ROOT_DIR:?ROOT_DIR must be set before sourcing linux/managed-links.sh}"
: "${MANAGED_LINKS:?MANAGED_LINKS must be initialised by shared/managed-links.sh first}"

MANAGED_LINKS+=(
  "${HOME}/.config/i3:${ROOT_DIR}/linux/configs/i3"
  "${HOME}/.config/polybar:${ROOT_DIR}/linux/configs/polybar"
  "${HOME}/.config/rofi:${ROOT_DIR}/linux/configs/rofi"
  "${HOME}/.config/dunst:${ROOT_DIR}/linux/configs/dunst"
  "${HOME}/.config/picom:${ROOT_DIR}/linux/configs/picom"
  "${HOME}/.config/xsettingsd:${ROOT_DIR}/linux/configs/xsettingsd"
  "${HOME}/.config/gtk-3.0:${ROOT_DIR}/linux/configs/gtk-3.0"
)
