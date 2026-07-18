# Linux monitor handling (Hyprland)

How external monitors work on this setup. The old autorandr/X11 flow this doc
used to describe is gone — Hyprland handles hotplug, per-monitor scale, and
lid switching natively; git history has the X11 version if ever needed.

## The mental model

Hyprland applies `monitor =` rules from `linux/configs/hypr/hyprland.conf`
(symlinked as `~/.config/hypr`) every time the set of connected outputs
changes. There is no profile daemon and nothing to save — plugging in a
monitor *is* the event that applies the rules.

```
monitor = eDP-1, preferred, auto, 1.5    # laptop panel, 1.5x scale
monitor = , preferred, auto, 1.25        # catch-all: any external monitor
```

- **Catch-all rule** (empty name): any monitor ever plugged in lights up at
  its preferred mode, auto-placed to the right, 1.25x scale. A brand-new
  projector or TV needs zero setup.
- **Named rules win over the catch-all.** To customize one monitor, add a rule
  naming its output (`DP-3`, `HDMI-A-1`, …) — or use the GUI below, which
  writes exactly such rules.
- **Clamshell mode** is handled by `linux/scripts/clamshell.sh` (linked as
  `~/.config/clamshell.sh`): it reads the ACPI lid state and disables or
  restores `eDP-1` accordingly. It runs on lid events (`bindl` switch binds),
  at startup, and on every config reload (`exec =` reruns on reload) — the
  reload case matters because reloads re-apply the static `eDP-1` rule, which
  would otherwise re-light a closed lid.

| Event | Result |
|---|---|
| Plug in any monitor | lights up extended, 1.25x, placed to the right |
| Close lid while docked | external becomes the only screen |
| Open lid | laptop panel comes back at 1.5x |
| Unplug | windows migrate to the remaining monitor |

**Fix-it button:** `$mod+Shift+m` runs `hyprctl reload`, re-evaluating all
monitor rules for the current hardware state.

## The GUI: nwg-displays

`nwg-displays` (Ubuntu archive, installed via `packages.txt`) is the visual
way to inspect and arrange monitors: drag the output rectangles, set
scale/mode/rotation/position, assign workspaces to monitors, then **Apply**.

It persists its result as plain Hyprland config:

| File | Contents |
|---|---|
| `~/.config/hypr/monitors.conf` | one `monitor = name, mode, position, scale` line per output |
| `~/.config/hypr/workspaces.conf` | `workspace = N, monitor:name` pinning lines |

Both are `source =`d from `hyprland.conf`, and both live *inside the repo*
(`~/.config/hypr` is a symlink to `linux/configs/hypr/`), so an arrangement
you apply in the GUI is versioned like any other config change — commit it if
you want to keep it.

Because named rules beat the catch-all, nwg-displays output composes cleanly
with the defaults: monitors it has configured get exact settings; anything
unknown still falls back to preferred/auto/1.25.

## Useful commands

```bash
hyprctl monitors            # connected outputs, modes, scales, positions
hyprctl monitors all        # includes disabled outputs (e.g. lid-closed eDP-1)
nwg-displays                # the GUI
hyprctl keyword monitor "eDP-1, disable"   # one-off: turn a panel off now
$mod+Shift+m                # re-apply all monitor rules (hyprctl reload)
```

## Scale notes

Wayland scale is per-monitor — there is no global DPI to juggle (the old
`Xft.dpi`/xsettingsd machinery had exactly one value for all screens). The
laptop's 2880x1800 panel runs at 1.5x; externals default to 1.25x. Fractional
scales are fine on Wayland-native apps; XWayland apps stay crisp because
`xwayland { force_zero_scaling = true }` is set — they render at 1x and
Hyprland doesn't upscale them.

Waybar auto-spans, and the backlight module only affects the laptop panel
(sysfs brightness is panel-only), same as before.
