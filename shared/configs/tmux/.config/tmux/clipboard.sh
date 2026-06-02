#!/usr/bin/env bash
# Read stdin and copy it to the system clipboard, using whatever tool exists.
# Used as the pipe target for tmux copy-mode (copy-pipe-and-cancel), so it must
# accept the selection on stdin. Order: macOS, then Wayland, then X11.
if command -v pbcopy >/dev/null 2>&1; then
    exec pbcopy
elif [ -n "$WAYLAND_DISPLAY" ] && command -v wl-copy >/dev/null 2>&1; then
    exec wl-copy
elif command -v xclip >/dev/null 2>&1; then
    exec xclip -selection clipboard
elif command -v xsel >/dev/null 2>&1; then
    exec xsel --clipboard --input
fi
