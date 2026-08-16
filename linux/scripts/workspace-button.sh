#!/bin/sh
# Render one Waybar workspace button. Click handling lives in config.jsonc;
# Only occupied workspaces are shown, plus the active workspace so a new
# workspace remains visible while it has no windows.

workspace_id="${1:?workspace id required}"
workspace_json="$(hyprctl workspaces -j 2>/dev/null || true)"
active_id="$(hyprctl activeworkspace -j 2>/dev/null | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*\([-0-9][0-9]*\).*/\1/p')"

if [ "${active_id}" = "${workspace_id}" ]; then
  printf '{"text":"%s","class":"active"}\n' "${workspace_id}"
elif printf '%s\n' "${workspace_json}" |
    sed -n '/"id"[[:space:]]*:[[:space:]]*'"${workspace_id}"'[[:space:]]*,/,/^[[:space:]]*}/p' |
    grep -Eq '"windows"[[:space:]]*:[[:space:]]*[1-9][0-9]*'; then
  printf '{"text":"%s","class":"occupied"}\n' "${workspace_id}"
else
  printf '{"text":"","class":"empty"}\n'
fi
