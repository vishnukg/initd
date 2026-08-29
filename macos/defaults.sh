#!/usr/bin/env bash
set -euo pipefail

# This script lives in macos/, so .. is the repository root.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/shared/lib/logging.sh"

# Better key repeat behavior for terminal-first workflows.
log "Setting key repeat defaults for terminal-first workflows."
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
defaults write NSGlobalDomain InitialKeyRepeat -int 15
defaults write NSGlobalDomain KeyRepeat -int 2
log_success "macOS defaults applied."

# Suppress the "Last login" line printed by /usr/bin/login on new terminal sessions.
touch "${HOME}/.hushlogin"
log_success "Suppressed last-login message (~/.hushlogin)."

# Desktop wallpaper: the same Bierstadt scan the Linux desktop uses, via the
# ~/.local/share/wallpapers MANAGED_LINKS entry (bootstrap runs link.sh before
# this script). desktoppr comes from the Brewfile; skip rather than fail so
# this script stays runnable on a machine that hasn't bootstrapped yet.
wallpaper="${HOME}/.local/share/wallpapers/classical-art/bierstadt-sierra-nevada.jpg"
if command -v desktoppr >/dev/null 2>&1 && [[ -f "${wallpaper}" ]]; then
  log "Setting desktop wallpaper."
  desktoppr "${wallpaper}"
  log_success "Wallpaper set on all displays."
else
  log_warn "Skipping wallpaper: desktoppr not installed or image missing."
fi
