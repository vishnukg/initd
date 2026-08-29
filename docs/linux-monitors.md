# Linux monitor handling (Hyprland)

`hyprmoncfg` owns monitor layout, named profiles, hotplug handling, and
closed-lid behavior. It is a terminal UI that applies changes safely and
reverts them unless confirmed.

The static rules at the top of `linux/configs/hypr/hyprland.lua` are only a
fallback before the first profile exists: the laptop panel and unknown external
monitors use their preferred modes at 1.33333x scale.

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

## Switching profiles from the bar

The Quickshell bar's monitor icon opens a profile switcher: a read-only list of
the connected displays with their current mode and scale, over the saved
profiles with the active one checked. Clicking a profile runs
`hyprmoncfg apply <name> --confirm-timeout 0`.

The switcher only *picks* between profiles that already exist. Creating and
arranging one is still a `hyprmoncfg` TUI job — the CLI's `save` only snapshots
whatever layout is applied right now, and there is no command to set an
individual monitor's mode.

`--confirm-timeout 0` is not optional. Interactively, `apply` asks
`Keep this configuration? [y/N] (auto-revert in 10s)`; with no terminal on the
other end it reads EOF, reverts the profile and exits 1, so a bar click would
appear to do nothing. Disabling the prompt gives up the auto-revert safety net,
which is acceptable only because every profile offered was saved from a layout
that already worked.

An apply can still be refused — hyprmoncfg validates before it commits, and a
profile saved against a different external monitor usually fails with
`layout overlaps: DP-1 intersects eDP-1`. The popup has already closed by then,
so the first line of stderr is raised as a notification rather than swallowed.

## Configuration ownership

The managed `~/.config/hyprmoncfg/` directory stores the portable profile
JSON, plus generated per-profile Lua and hyprlang fallbacks. Commit intentional
profile changes there.

Profiles that share the same connected displays cannot be auto-selected from
hardware identity alone. The committed `External screen only`, `External
above`, and `External mirrored` profiles all match the laptop panel plus the
BenQ RD320U, so explicitly apply the desired external layout:

```bash
hyprmoncfg apply "External screen only"
hyprmoncfg apply "External above"
hyprmoncfg apply "External mirrored"
```

The BenQ RD320U uses a sharp 1.06667x scale (3600x2025 logical workspace) in
each external profile. This keeps the display readable while reducing the
input latency observed at 1.25x fractional scaling.

`hyprmoncfg` generates the active `~/.config/hypr/hyprmoncfg-monitors.lua`
itself. Do not commit or manually edit that file: `hyprland.lua` loads it with
`dofile(os.getenv("HOME") .. "/.config/hypr/hyprmoncfg-monitors.lua")` at the
end of the file (after everything else, so nothing can override the applied
layout), and the daemon rewrites it as profiles change. `~/.config/hypr/monitors.lua`
is a leftover from an older `hyprmoncfg` version that wrote there instead;
`hyprland.lua` still loads it too, via `pcall(require, "monitors")`, but
`hyprmoncfg` itself now leaves it alone — anything you put there yourself is
kept, and loaded before the daemon's own file.

That `dofile` is deliberately left unprotected. `hyprmoncfg` verifies after every
reload that its rules actually ran and re-appends that exact line when they did
not, so wrapping it in `pcall` only earns a duplicate loader on the next apply.
Because the target is generated and gitignored, it does not exist on a fresh
bootstrap until the first profile is saved — and a missing target makes `dofile`
abort config parsing. `linux/setup.sh:seed_hyprmoncfg_monitors` closes that gap by
writing a comment-only stub when the file is absent, which leaves the static
fallback rules in `hyprland.lua` in effect until `hyprmoncfg` overwrites it.

Keep one profile per real desk, dock, projector, or travel setup; every JSON
profile is considered when the daemon chooses a match.
