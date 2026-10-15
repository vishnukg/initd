#!/usr/bin/env bash

# Source of truth for cross-platform managed symlinks plus git-profile helpers.
# Platform-specific entries are appended in <platform>/managed-links.sh.

: "${ROOT_DIR:?ROOT_DIR must be set before sourcing shared/managed-links.sh}"

# Format: "home path:repo path".
# Cross-platform configs only. Add platform-only entries in <platform>/managed-links.sh.
# ~/.gitconfig points at the single base config; the machine-local email/overrides
# live in shared/configs/git/local.gitconfig (gitignored), included from gitconfig.
MANAGED_LINKS=(
  "${HOME}/.gitconfig:${ROOT_DIR}/shared/configs/git/gitconfig"
  "${HOME}/.colima/_templates/default.yaml:${ROOT_DIR}/shared/configs/colima/.colima/_templates/default.yaml"
  "${HOME}/.config/fish:${ROOT_DIR}/shared/configs/fish/.config/fish"
  "${HOME}/.config/ghostty:${ROOT_DIR}/shared/configs/ghostty/.config/ghostty"
  "${HOME}/.config/kitty:${ROOT_DIR}/shared/configs/kitty/.config/kitty"
  "${HOME}/.config/mise:${ROOT_DIR}/shared/configs/mise/.config/mise"
  "${HOME}/.config/nvim:${ROOT_DIR}/shared/configs/nvim/.config/nvim"
  "${HOME}/.config/starship.toml:${ROOT_DIR}/shared/configs/starship/.config/starship.toml"
  "${HOME}/.config/tmux:${ROOT_DIR}/shared/configs/tmux/.config/tmux"
  # Not a config, but the wallpapers are platform-neutral art and hyprpaper
  # needs a stable path to them. Linking them to the XDG data dir beats the
  # old ~/.config/hypr/../wallpaper/ hop, which only resolved because the
  # hypr link happened to point one directory below them.
  "${HOME}/.local/share/wallpapers:${ROOT_DIR}/shared/wallpaper"
)

# The exe.dev dev box - SSH client config and kitty's shortcuts to it: personal
# machines only. A work machine gets nothing dev-box related and keeps its own
# ~/.ssh/config untouched. "Personal" is the email
# git-profile.mjs wrote into local.gitconfig, so bootstraps set the Git
# profile BEFORE linking.
# Global/system git config are ignored: git parses them even with --file,
# and an unreadable ~/.gitconfig would otherwise read as "not personal".
if [[ "$(GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git config --file "${ROOT_DIR}/shared/configs/git/local.gitconfig" user.email 2>/dev/null || true)" == "vishnukg@gmail.com" ]]; then
  MANAGED_LINKS+=(
    "${HOME}/.ssh/config:${ROOT_DIR}/shared/configs/ssh/.ssh/config"
    "${HOME}/.config/kitty-dev-box.conf:${ROOT_DIR}/shared/configs/kitty/dev-box.conf"
  )
fi
