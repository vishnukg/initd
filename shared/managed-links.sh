#!/usr/bin/env bash

# Source of truth for cross-platform managed symlinks plus git-profile helpers.
# Platform-specific entries are appended in <platform>/managed-links.sh.

: "${ROOT_DIR:?ROOT_DIR must be set before sourcing shared/managed-links.sh}"

# shellcheck disable=SC1091
source "${ROOT_DIR}/shared/lib/fs.sh"

# Format: "home path:repo path".
# Cross-platform configs only. Add platform-only entries in <platform>/managed-links.sh.
# ~/.gitconfig points at the single base config; the machine-local email/overrides
# live in shared/configs/git/local.gitconfig (gitignored), included from gitconfig.
MANAGED_LINKS=(
  "${HOME}/.gitconfig:${ROOT_DIR}/shared/configs/git/gitconfig"
  "${HOME}/.config/fish:${ROOT_DIR}/shared/configs/fish/.config/fish"
  "${HOME}/.config/ghostty:${ROOT_DIR}/shared/configs/ghostty/.config/ghostty"
  "${HOME}/.config/mise:${ROOT_DIR}/shared/configs/mise/.config/mise"
  "${HOME}/.config/nvim:${ROOT_DIR}/shared/configs/nvim/.config/nvim"
  "${HOME}/.config/starship.toml:${ROOT_DIR}/shared/configs/starship/.config/starship.toml"
  "${HOME}/.config/tmux:${ROOT_DIR}/shared/configs/tmux/.config/tmux"
)
