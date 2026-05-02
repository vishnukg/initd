#!/usr/bin/env bash
set -euo pipefail

# Better key repeat behavior for terminal-first workflows.
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
defaults write NSGlobalDomain InitialKeyRepeat -int 15
defaults write NSGlobalDomain KeyRepeat -int 2
