#!/bin/bash
PYTHON_SCRIPT='
import json, sys

colors = ["", "#a6e3a1", "#89b4fa", "#cba6f7", "#74c7ec", "#b4befe", "#94e2d5", "#f9e2af", "#f5c2e7", "#89b4fa", "#a6e3a1"]

def dim(hex_color, factor=0.8):
    r = int(int(hex_color[1:3], 16) * factor)
    g = int(int(hex_color[3:5], 16) * factor)
    b = int(int(hex_color[5:7], 16) * factor)
    return f"#{r:02x}{g:02x}{b:02x}"

try:
    workspaces = json.load(sys.stdin)
    workspaces.sort(key=lambda w: w["num"])
    parts = []
    for ws in workspaces:
        num = min(ws["num"], len(colors) - 1)
        color = colors[num]
        name = ws["name"]
        click = f"i3-msg workspace \"{name}\""
        if ws["focused"]:
            parts.append(f"%{{F{color}}}%{{u{color}}}%{{+u}}%{{A1:{click}:}}%{{O8}}%{{T3}}{name}%{{T-}}%{{O8}}%{{A}}%{{-u}}%{{F-}}")
        elif ws["urgent"]:
            parts.append(f"%{{F#f9e2af}}%{{u#f9e2af}}%{{+u}}%{{A1:{click}:}}%{{O8}}%{{T3}}{name}%{{T-}}%{{O8}}%{{A}}%{{-u}}%{{F-}}")
        else:
            parts.append(f"%{{F{dim(color)}}}%{{A1:{click}:}}%{{O8}}%{{T3}}{name}%{{T-}}%{{O8}}%{{A}}%{{F-}}")
    print("%{O6}".join(parts))
except (json.JSONDecodeError, KeyError):
    pass
'

print_workspaces() {
    i3-msg -t get_workspaces 2>/dev/null | python3 -c "$PYTHON_SCRIPT" 2>/dev/null
}

print_workspaces

# Outer loop reconnects after i3 reload/restart drops the IPC subscription
while true; do
    i3-msg -t subscribe '["workspace"]' 2>/dev/null | while read -r _; do
        print_workspaces
    done
    sleep 0.5
    print_workspaces
done
