#!/usr/bin/env bash

# Linux-only managed symlinks. Appended to the shared MANAGED_LINKS array.
# Wayland/Hyprland stack only.

: "${ROOT_DIR:?ROOT_DIR must be set before sourcing linux/managed-links.sh}"
: "${MANAGED_LINKS:?MANAGED_LINKS must be initialised by shared/managed-links.sh first}"

MANAGED_LINKS+=(
  "${HOME}/.config/hypr:${ROOT_DIR}/linux/configs/hypr"
  "${HOME}/.config/hyprmoncfg:${ROOT_DIR}/linux/configs/hyprmoncfg"
  "${HOME}/.config/quickshell:${ROOT_DIR}/linux/configs/quickshell"
  "${HOME}/.config/rofi:${ROOT_DIR}/linux/configs/rofi"
  "${HOME}/.config/dunst:${ROOT_DIR}/linux/configs/dunst"
  "${HOME}/.config/fontconfig:${ROOT_DIR}/linux/configs/fontconfig"
  "${HOME}/.config/gtk-3.0:${ROOT_DIR}/linux/configs/gtk-3.0"
  "${HOME}/.config/pipewire:${ROOT_DIR}/linux/configs/pipewire"
  # A real unit, not a drop-in: a oneshot no-op that hyprland.lua starts from
  # its autostart block so graphical-session.target is reached under Hyprland
  # the way it is under GNOME. Nothing enables it; hyprland.lua starts it.
  "${HOME}/.config/systemd/user/initd-hyprland-session.service:${ROOT_DIR}/linux/configs/systemd/user/initd-hyprland-session.service"
)

# Berkeley Mono — licensed font, gitignored (see .gitignore). shared/fonts/ is
# a clone of the PRIVATE vishnukg/fonts repo, synced by shared/lib/fonts.sh
# earlier in bootstrap; the link is skipped on machines where that sync could
# not run (no gh auth, no access to the repo).
# fontconfig scans ~/.local/share/fonts recursively.
if [[ -d "${ROOT_DIR}/shared/fonts/berkeley-mono" ]]; then
  MANAGED_LINKS+=( "${HOME}/.local/share/fonts/berkeley-mono:${ROOT_DIR}/shared/fonts/berkeley-mono" )
fi
