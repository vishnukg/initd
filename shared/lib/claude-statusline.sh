#!/usr/bin/env bash
set -euo pipefail

# Ensures ~/.claude/settings.json points Claude Code's statusLine hook at
# shared/configs/tmux's claude-statusline-hook.sh, which is what feeds the
# Claude pill in the tmux status line with server-authoritative rate-limit
# data (see that script's header for why). Run standalone or from a
# platform bootstrap, AFTER link.sh so the hook's target path already
# resolves through the ~/.config/tmux symlink.
#
# Not a MANAGED_LINKS symlink: ~/.claude/settings.json also holds
# user/machine-specific Claude Code settings (modelSettings, theme, ...)
# this repo has no business overwriting wholesale. Same JSON-merge-in-place
# pattern as macos/bootstrap.sh:ensure_docker_config, just placed in
# shared/ rather than repeated per-platform - ~/.claude lives under $HOME
# identically on macOS and Linux, nothing here is platform-specific.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# shellcheck disable=SC1091
source "${ROOT_DIR}/shared/lib/logging.sh"

main() {
  local settings_path="${HOME}/.claude/settings.json"
  mkdir -p "${HOME}/.claude"

  python3 - "${settings_path}" <<'PY' \
    || { log_error "Failed to update ${settings_path}"; exit 1; }
import json
import os
import sys

path = sys.argv[1]
config = {}
if os.path.exists(path):
    with open(path) as f:
        config = json.load(f)

wanted_status_line = {
    "type": "command",
    "command": "~/.config/tmux/claude-statusline-hook.sh",
    "refreshInterval": 60,
}

if config.get("statusLine") != wanted_status_line:
    config["statusLine"] = wanted_status_line
    with open(path, "w") as f:
        json.dump(config, f, indent=2)
        f.write("\n")
PY

  log_success "Claude Code statusLine hook configured (~/.claude/settings.json)."
}

main
