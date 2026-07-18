# Linux monitor handling (Hyprland)

How external monitors work on this setup. The old autorandr/X11 flow this doc
used to describe is gone — Hyprland handles hotplug, per-monitor scale, and
lid switching natively; git history has the X11 version if ever needed.

## The mental model

Hyprland applies `monitor =` rules from `linux/configs/hypr/hyprland.conf`
(symlinked as `~/.config/hypr`) every time the set of connected outputs
changes. There is no profile daemon: plugging in a monitor is the event that
applies the defaults, while nwg-displays can optionally save named overrides.
Think of the setup as three separate actors:

| Actor | Responsibility |
|---|---|
| Hyprland | detects outputs and applies mode, scale, and position rules |
| `clamshell.sh` | enables or disables the laptop panel in response to the lid |
| nwg-displays | edits saved monitor rules; it does not need to stay running |

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
  restores `eDP-1` accordingly. It disables the panel only when another
  monitor is active, preserves the focused workspace across the monitor
  migration, and skips redundant changes. It runs immediately on lid events
  (`bindl` switch binds), plus after a short settling delay at startup and on
  every config reload (`exec =` reruns on reload). The reload case matters
  because reloads re-apply the static `eDP-1` rule, which would otherwise
  re-light a closed lid.

## Everyday scenarios

| What happens | Result |
|---|---|
| Start with the laptop by itself | `eDP-1` uses its preferred mode at 1.5x |
| Plug in an external with the lid open | both screens work; the external uses its preferred mode, 1.25x, auto-positioned to the right |
| Close the lid after connecting an external | `clamshell.sh` disables `eDP-1`; the external becomes the only screen |
| Open the lid while still connected | `eDP-1` returns at 1.5x; both screens work |
| Unplug the external with the lid open | its workspaces and windows migrate to the laptop panel |
| Connect an unfamiliar monitor | the catch-all rule gives it preferred mode, 1.25x, and automatic position |
| Connect multiple external monitors | every unknown output gets the catch-all; Hyprland extends them sequentially to the right |

### Recommended docking order

When connecting: keep the lid open, plug in the monitor, wait for both screens,
then close the lid if external-only mode is wanted.

When disconnecting: open the lid, wait for the laptop panel, then unplug the
external. This order guarantees that an active output is always available.

### Closed-lid cable changes

The clamshell script listens for lid events and config reloads, not Hyprland's
monitor-added/removed IPC events. Consequently, changing cables while the lid
remains closed is an edge case:

| Situation | What to do |
|---|---|
| Plug in an external while the lid is already closed | the external is detected, but clamshell state may not be reassessed until a lid event or reload; open/close the lid or reload |
| Unplug the external while the lid remains closed | avoid this because it may be the only active output; open the lid first |
| Laptop panel remains logically active behind a closed lid | open/close the lid or reload |
| Reload while the lid is closed | the static rule may briefly enable `eDP-1`; after one second the script disables it and restores the focused workspace |

### Windows and workspaces

Removing an output makes Hyprland migrate its workspaces and windows to an
output that remains. Reconnecting the output does not necessarily move those
workspaces back: without explicit workspace rules, new workspaces appear on
the currently focused monitor. This flexible behavior is why
`workspaces.conf` is left empty by default.

Workspace assignments made in nwg-displays can create a fixed split (for
example, workspaces 1–5 on an external and 6–10 on the laptop), but that also
makes docking less flexible. Add assignments only when a permanent layout is
more useful than automatic migration.

**Fix-it button:** `$mod+Shift+m` runs `hyprctl reload`, re-evaluating all
monitor rules for the current hardware state.

## The GUI: nwg-displays

`nwg-displays` (Ubuntu archive, installed via `packages.txt`) is the visual
way to inspect and arrange monitors: drag the output rectangles, set
scale/mode/rotation/position, assign workspaces to monitors, then **Apply**.
It is a Hyprland configuration generator, not a hotplug/profile daemon;
Hyprland still performs the actual output configuration and automatic reload.

It persists its result as plain Hyprland config:

| File | Contents |
|---|---|
| `~/.config/hypr/monitors.conf` | one `monitor = name, mode, position, scale` line per output |
| `~/.config/hypr/workspaces.conf` | `workspace = N, monitor:name` pinning lines |

Both are `source =`d from `hyprland.conf`, and both live *inside the repo*
(`~/.config/hypr` is a symlink to `linux/configs/hypr/`), so an arrangement
you apply in the GUI is versioned like any other config change — commit it if
you want to keep it, or inspect/revert it with `git diff` if not. The files are
writable through their symlinks, so nwg-displays does not need a custom output
path.

Because named rules beat the catch-all, nwg-displays output composes cleanly
with the defaults: monitors it has configured get exact settings; anything
unknown still falls back to preferred/auto/1.25.

nwg-displays rewrites `monitors.conf` with the layout currently represented in
the GUI; it does not append an unlimited collection of per-monitor profiles.
The practical result is:

| Later connection | Rule used |
|---|---|
| Reconnect a monitor still named in `monitors.conf` | its saved custom rule |
| Connect a different or unknown monitor | the Hyprland catch-all defaults |
| Apply a layout for that different monitor | nwg-displays replaces `monitors.conf` with the newly generated layout |

This means any number of monitors can still be connected safely. A saved rule
is optional customization, while the catch-all remains the reliable fallback
for everything else.

### Safe first use

1. Connect the external display and **open the laptop lid before pressing
   Apply**.
2. Use scale `1.5` for the 2880x1800 laptop panel and `1.25` for the 4K
   external display, then arrange their relative positions.
3. Enable **Use monitor description** if a dock sometimes exposes the same
   display under different connector names such as `DP-1` and `DP-2`.
4. Initially leave workspace assignments unchanged. Explicit assignments pin
   workspaces to outputs and can affect which workspace Hyprland focuses when
   an output is removed.
5. Press **Apply**, verify both displays, and choose **Keep** in the confirmation
   window. Review the generated files with `git diff` before committing them.

Applying while the lid is closed can make nwg-displays record
`monitor=eDP-1,disable` in `monitors.conf`, because the panel is inactive at
that moment. The clamshell script can restore the panel when the lid opens,
but the saved disable rule would cause an unnecessary disable/enable cycle on
future reloads and could briefly disturb workspace placement. Open the lid and
apply again to save a clean two-display layout.

Ubuntu currently packages nwg-displays `0.3.26-1`. It works with this setup's
Hyprland 0.53 configuration format and covers normal layout, mode, scale, and
rotation. Upstream `0.3.28` restored mirror and 10-bit controls that are absent
from this package; newer releases also add profile features and Hyprland 0.55
Lua output. None of those newer features is required for the basic setup
described here.

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
