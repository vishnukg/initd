# Linux monitor handling (Hyprland)

`hyprmoncfg` owns monitor layout, named profiles, hotplug handling, and
closed-lid behavior. It is a terminal UI that applies changes safely and
reverts them unless confirmed.

The static rules at the top of `linux/configs/hypr/hyprland.lua` are only a
fallback before the first profile exists: the laptop panel and unknown external
monitors use their preferred modes at 1.25x scale.

## Create profiles

Start a Hyprland session, then launch:

```bash
hyprmoncfg
```

Drag displays on the canvas; edit mode, scale, rotation, mirroring, and
workspace placement in the side panel. Press `s`, name the layout (for example
`desk` or `projector`), then press Enter. The daemon auto-selects the best
profile whenever monitors change or the laptop lid closes.

Useful commands:

```bash
hyprctl monitors              # inspect connected outputs
hyprmoncfg                    # open the layout editor
hyprmoncfg apply desk         # apply a saved profile
systemctl --user status hyprmoncfgd
```

## Configuration ownership

The managed `~/.config/hyprmoncfg/` directory stores the portable profile
JSON, plus generated per-profile Lua and hyprlang fallbacks. Commit intentional
profile changes there.

`hyprmoncfg` generates the active `~/.config/hypr/monitors.lua` itself. Do not
commit or manually edit that file: `hyprland.lua` imports it with
`pcall(require, "monitors")`, and the daemon rewrites it as profiles change.
Keep one profile per real desk, dock, projector, or travel setup; every JSON
profile is considered when the daemon chooses a match.
