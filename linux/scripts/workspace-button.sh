#!/bin/sh
# Render one Waybar workspace button. Click handling lives in config.jsonc;
# this only provides the active class for styling.

workspace_id="${1:?workspace id required}"
workspace_json="$(hyprctl workspaces -j 2>/dev/null || true)"
active_id="$(hyprctl activeworkspace -j 2>/dev/null | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*\([-0-9][0-9]*\).*/\1/p')"

if ! printf '%s\n' "${workspace_json}" | grep -Eq '"id"[[:space:]]*:[[:space:]]*'"${workspace_id}"'([,}])'; then
  printf '{"text":"","class":"empty"}\n'
  exit 0
fi

if [ "${active_id}" = "${workspace_id}" ]; then
  printf '{"text":"%s","class":"active"}\n' "${workspace_id}"
else
  printf '{"text":"%s","class":"inactive"}\n' "${workspace_id}"
fi
