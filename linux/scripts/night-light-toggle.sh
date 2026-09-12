#!/bin/sh
# Compatibility for existing keybindings until the next setup run.
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
exec node "${SCRIPT_DIR}/night-light-toggle.mjs" "$@"
