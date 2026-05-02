#!/usr/bin/env bash
set -euo pipefail

echo "==> Setting key repeat defaults for terminal-first workflows."

# Better key repeat behavior for terminal-first workflows.
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
defaults write NSGlobalDomain InitialKeyRepeat -int 15
defaults write NSGlobalDomain KeyRepeat -int 2
